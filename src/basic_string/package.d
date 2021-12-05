/**
	Mutable @nogc @safe string struct using `std.experimental.allocator` for allocations.

	License:   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
	Authors:   $(HTTP github.com/submada/basic_string, Adam Búš)
*/
module basic_string;

import std.traits : Unqual, Unconst, isSomeChar, isSomeString;
import std.meta : AliasSeq;

import basic_string.internal.mallocator;


debug import std.stdio : writeln;

/**
	True if `T` is a `BasicString` or implicitly converts to one, otherwise false.
*/
template isBasicString(T...)
if(T.length == 1){
	enum isBasicString = is(Unqual!(T[0]) == BasicString!Args, Args...);
}



/**
	The `BasicString` is the generalization of struct string for character of type `char`, `wchar` or `dchar`.

	`BasicString` use utf-8, utf-16 or utf-32 encoding.

	`BasicString` use SSO (Small String Optimization).

	Template parameters:

		`_Char` Character type. (`char`, `wchar` or `dchar`).

		`_Allocator` Type of the allocator object used to define the storage allocation model. By default Mallocator is used.

		`_Padding` Additional size of struct `BasicString`, increase max length of small string.

*/
template BasicString(
	_Char,
	_Allocator = Mallocator,
	size_t _Padding = 0,
)
if(isSomeChar!_Char && is(Unqual!_Char == _Char)){
private:
	import std.experimental.allocator.common : stateSize;
	import std.range : isInputRange, ElementEncodingType, isRandomAccessRange;
	import std.traits : Unqual, isIntegral, hasMember, isArray, isSafe;

	import basic_string.internal.encoding;

	enum isOtherString(T) =
		isSomeString!T
		&& !is(Unqual!(ElementEncodingType!T) == Unqual!_Char);

	enum isSmallCharArray(T) = is(T : C[N], C, size_t N)
		&& isSomeChar!C
		&& N <= Short.capacity
		&& C.sizeof <= _Char.sizeof;

	enum isCharArray(T) = is(T : C[N], C, size_t N)
		&& isSomeChar!C;

	version(BigEndian){
		static assert(0, "big endian systems are not supported");
	}
	version(LittleEndian){

		struct Long{
			size_t capacity;
			size_t length;
			_Char* ptr;
			ubyte[_Padding] padding;

			@property isLong()scope const pure nothrow @safe @nogc{
				return (capacity & 0x1) == 0;
			}

			enum size_t maxCapacity = (size_t.max / _Char.sizeof) & ~cast(size_t)0x1;
		}

		static if(Long.sizeof / _Char.sizeof <= ubyte.max)
			alias ShortLength = ubyte;
		else static if(Long.sizeof / _Char.sizeof <= ushort.max)
			alias ShortLength = ushort;
		else static if(Long.sizeof / _Char.sizeof <= uint.max)
			alias ShortLength = uint;
		else static if(Long.sizeof / _Char.sizeof <= ulong.max)
			alias ShortLength = ulong;
		else static assert(0, "no impl");

		struct Short{
			static assert((Long.sizeof - Header.sizeof) % _Char.sizeof == 0);

			union Header{
				struct{
					ubyte flag = 0x1;
					ShortLength length;
				}
				_Char padding;
			}
			Header header;
			alias header this;

			enum size_t capacity = (Long.sizeof - Header.sizeof) / _Char.sizeof;
			_Char[capacity] data;


			@property isShort()scope const pure nothrow @safe @nogc{
				return (flag & 0x1) == 1;
			}

			void setShort()scope pure nothrow @safe @nogc{
				flag = 0x1;
			}
		}

		static assert(Long.sizeof == Short.sizeof);
	}
	else static assert(0, "no impl");


	struct Impl{}


	static void _memmove(T)(scope T* target, scope const(T)* source, size_t length)@trusted{
		import core.stdc.string : memmove;

		memmove(target, source, length * T.sizeof);
		/+version(D_BetterC){
			import core.stdc.string : memmove;

			memmove(target, source, length * T.sizeof);
		}
		else{
			target[0 .. length] = source[0 .. length];
		}+/

	}
	static void _memcpy(T)(scope T* target, scope const(T)* source, size_t length)@trusted{
		import core.stdc.string : memcpy;

		memcpy(target, source, length * T.sizeof);
		/+
		version(D_BetterC){
			import core.stdc.string : memcpy;

			memcpy(target, source, length * T.sizeof);
		}
		else{
			target[0 .. length] = source[0 .. length];
		}+/
	}

public:

	struct BasicString{
		/**
			True if allocator doesn't have state.
		*/
		enum hasStatelessAllocator = stateSize!_Allocator == 0;



		/**
			Character type. (`char`, `wchar` or `dchar`).
		*/
		alias Char = _Char;



		/**
			Type of the allocator object used to define the storage allocation model. By default Mallocator is used.
		*/
		alias Allocator = _Allocator;

private:

		static if(hasStatelessAllocator){
			alias _allocator = Allocator.instance;
			alias AllocatorWithState = AliasSeq!();
		}
		else{
			Allocator _allocator;
			alias AllocatorWithState = AliasSeq!Allocator;
		}


		union{
			Short _short;
			Long _long;
			size_t[Long.sizeof / size_t.sizeof] _raw;

			static assert(typeof(_raw).sizeof == Long.sizeof);
		}

		enum safeAllocate = isSafe!((ref Unconst!(typeof(allocator)) allocator){
			size_t capacity = size_t.max;

			allocator.allocate(capacity);
		});

		pure nothrow @nogc @trusted{
			//_long:
			@property inout(Char)* _long_ptr()inout scope return{
				assert(_long.isLong);

				return _long.ptr;
			}

			@property inout(void)[] _long_data()inout scope return{
				assert(_long.isLong);

				return (cast(void*)_long.ptr)[0 .. _long.capacity * Char.sizeof];
			}

			@property size_t _long_capacity()const scope{
				assert(_long.isLong);

				return _long.capacity;
			}

			@property size_t _long_length()const scope{
				assert(_long.isLong);

				return _long.length;
			}

			@property inout(Char)[] _long_chars()inout scope return{
				assert(_long.isLong);

				return _long.ptr[0 .. _long.length];
			}

			@property inout(Char)[] _long_all_chars()inout scope return{
				assert(_long.isLong);

				return _long.ptr[0 .. _long.capacity];
			}

			//_short:
			@property inout(Char)* _short_ptr()inout return{
				assert(_short.isShort);

				return _short.data.ptr;
			}

			@property inout(void)[] _short_data()inout return{
				assert(_short.isShort);

				return (cast(void*)_short.data.ptr)[0 .. _short.capacity * Char.sizeof];
			}
		}
		pure nothrow @nogc @safe{

			@property size_t _short_capacity()const scope{
				assert(_short.isShort);

				return _short.capacity;
			}

			@property auto _short_length()const scope{
				assert(_short.isShort);

				return _short.length;
			}

			@property inout(Char)[] _short_chars()inout return{
				assert(_short.isShort);

				return _short.data[0 .. _short.length];
			}

			@property inout(Char)[] _short_all_chars()inout return{
				assert(_short.isShort);

				return _short.data[];
			}
		}

		pure nothrow @nogc{

			@property bool _sso()const scope @trusted{
				assert(_long.isLong != _short.isShort);
				return _short.isShort;
			}

			@property void _length(in size_t len)scope @system{
				assert(len <= capacity);

				if(_sso)
					_short.length = cast(ShortLength)len;
				else
					_long.length = len;
			}

			@property inout(Char)[] _chars()inout scope return @trusted{
				return _sso
					? _short_chars()
					: _long_chars();
			}

			@property inout(Char)[] _all_chars()inout scope return @trusted{
				return _sso
					? _short_all_chars()
					: _long_all_chars();
			}
		}


		//allocation:
		Char[] _allocate(in size_t capacity){
			void[] data = _allocator.allocate(capacity * Char.sizeof);

			return (()@trusted => (cast(Char*)data.ptr)[0 .. capacity])();
		}

		bool _deallocate(scope Char[] cdata){
			void[] data = (()@trusted => (cast(void*)cdata.ptr)[0 .. cdata.length * Char.sizeof])();

			static if(safeAllocate)
				return (()@trusted => _allocator.deallocate(data))();
			else
				return _allocator.deallocate(data);
		}

		Char[] _reallocate(scope return Char[] cdata, in size_t length, in size_t new_capacity){
			void[] data = (()@trusted => (cast(void*)cdata.ptr)[0 .. cdata.length * Char.sizeof])();

			static if(hasMember!(typeof(_allocator), "reallocate")){
				static if(safeAllocate)
					const bool reallocated =
						(()@trusted => _allocator.reallocate(data, new_capacity * Char.sizeof))();
				else
					const bool reallocated = _allocator.reallocate(data, new_capacity * Char.sizeof);
			}
			else
				enum bool reallocated = false;

			if(reallocated){
				assert(data.length / Char.sizeof == new_capacity);
				return (()@trusted => (cast(Char*)data.ptr)[0 .. new_capacity])();
			}

			Char[] new_cdata = _allocate(new_capacity);
			()@trusted{
				_memcpy(new_cdata.ptr, cdata.ptr, length);  //new_cdata[0 .. length] = cdata[0 .. length];
			}();

			static if(safeAllocate)
				()@trusted{
					_allocator.deallocate(data);
				}();
			else
				_allocator.deallocate(data);

			return new_cdata;
		}

		Char[] _reallocate_optional(scope return Char[] cdata, in size_t new_capacity)@trusted{
			void[] data = (cast(void*)cdata.ptr)[0 .. cdata.length * Char.sizeof];

			static if(hasMember!(typeof(_allocator), "reallocate")){
				static if(safeAllocate)
					bool re =
						(()@trusted => _allocator.reallocate(data, new_capacity * Char.sizeof))();

				else
					bool re = _allocator.reallocate(data, new_capacity * Char.sizeof);

				if(re){
					assert(data.length / Char.sizeof == new_capacity);
					return (cast(Char*)data.ptr)[0 .. new_capacity];
				}
			}

			return cdata;
		}

	//reduce/expand:
		void _reduce_move(in size_t pos, in size_t n)scope pure nothrow @system @nogc{
			assert(pos <= length);
			assert(pos >= n);
			assert(n > 0);

			auto chars = _chars;
			const len = chars.length - pos;

			_memmove(
				chars.ptr + (pos - n),
				chars.ptr + pos,
				len
			);

			_length = chars.length - n;
		}

		Char[] _expand_move(in size_t pos, in size_t n)scope return {
			assert(n > 0);

			auto chars = _chars;
			if(pos >= chars.length)
				return _expand(n);

			const new_length = chars.length + n;
			reserve(new_length);


			return ()@trusted{
				auto chars = _chars;
				_length = new_length;

				const len = chars.length - pos;

				_memmove(
					chars.ptr + pos + n,
					chars.ptr + pos,
					len
				);

				return (chars.ptr + pos)[0 .. n];
			}();
		}

		Char[] _expand(in size_t n)scope return{
			const old_length = length;
			const new_length = old_length + n;

			reserve(new_length);

			return ()@trusted{
				auto chars = _chars;
				//assert(capacity >= new_length);
				_length = new_length;

				return chars.ptr[old_length .. new_length];
			}();
		}

public:

		/**
			Maximal capacity of string, in terms of number of characters (utf code units).
		*/
		alias MaximalCapacity = Long.maxCapacity;



		/**
			Minimal capacity of string (same as maximum capacity of small string), in terms of number of characters (utf code units).

			Examples:
				--------------------
				BasicString!char str;
				assert(str.empty);
				assert(str.capacity == BasicString!char.MinimalCapacity);
				assert(str.capacity > 0);
				--------------------
		*/
		alias MinimalCapacity = Short.capacity;



		/**
			Returns copy of allocator.
		*/
		@property auto allocator()inout{
			return _allocator;
		}



		/**
			Returns whether the string is empty (i.e. whether its length is 0).

			Examples:
				--------------------
				BasicString!char str;
				assert(str.empty);

				str = "123";
				assert(!str.empty);
				--------------------
		*/
		@property bool empty()const scope pure nothrow @safe @nogc{
			return length == 0;
		}



		/**
			Returns the length of the string, in terms of number of characters (utf code units).

			This is the number of actual characters that conform the contents of the `BasicString`, which is not necessarily equal to its storage capacity.

			Examples:
				--------------------
				BasicString!char str = "123";
				assert(str.length == 3);

				BasicString!wchar wstr = "123";
				assert(wstr.length == 3);

				BasicString!dchar dstr = "123";
				assert(dstr.length == 3);

				--------------------
		*/
		@property size_t length()const scope pure nothrow @trusted @nogc{
			return _sso
				? _short_length
				: _long_length;
		}



		/**
			Returns the size of the storage space currently allocated for the `BasicString`, expressed in terms of characters (utf code units).

			This capacity is not necessarily equal to the string length. It can be equal or greater, with the extra space allowing the object to optimize its operations when new characters are added to the `BasicString`.

			Notice that this capacity does not suppose a limit on the length of the `BasicString`. When this capacity is exhausted and more is needed, it is automatically expanded by the object (reallocating it storage space).

			The capacity of a `BasicString` can be altered any time the object is modified, even if this modification implies a reduction in size.

			The capacity of a `BasicString` can be explicitly altered by calling member `reserve`.

			Examples:
				--------------------
				BasicString!char str;
				assert(str.capacity == BasicString!char.MinimalCapacity);

				str.reserve(str.capacity + 1);
				assert(str.capacity > BasicString!char.MinimalCapacity);
				--------------------
		*/
		@property size_t capacity()const scope pure nothrow @trusted @nogc{
			return _sso
				? _short_capacity
				: _long_capacity;
		}



		/**
			Return pointer to the first element.

			The pointer  returned may be invalidated by further calls to other member functions that modify the object.

			Examples:
				--------------------
				BasicString!char str = "123";
				char* ptr = str.ptr;
				assert(ptr[0 .. 3] == "123");
				--------------------

		*/
		@property inout(Char)* ptr()inout scope return pure nothrow @system @nogc{
			return _sso
				? _short_ptr
				: _long_ptr;
		}



		/**
			Return `true` if string is small (Small String Optimization)
		*/
		@property bool small()const scope pure nothrow @safe @nogc{
			return _sso;
		}



		/**
			Return `true` if string is valid utf string.
		*/
		@property bool valid()const scope pure nothrow @safe @nogc{
			return validate(_chars[]);
		}



		/**
			Returns first utf code point(`dchar`) of the `BasicString`.

			This function shall not be called on empty strings.

			Examples:
				--------------------
				BasicString!char str = "á123";

				assert(str.frontCodePoint == 'á');
				--------------------
		*/
		@property dchar frontCodePoint()const scope pure nothrow @trusted @nogc{
			auto chars = _all_chars;
			return decode(chars);
		}



		/**
			Returns the first character(utf8: `char`, utf16: `wchar`, utf32: `dchar`) of the `BasicString`.

			This function shall not be called on empty strings.

			Examples:
				--------------------
				BasicString!char str = "123";

				assert(str.frontCodeUnit == '1');
				--------------------

				--------------------
				BasicString!char str = "á23";

				immutable(char)[2] a = "á";
				assert(str.frontCodeUnit == a[0]);
				--------------------

				--------------------
				BasicString!char str = "123";

				str.frontCodeUnit = 'x';

				assert(str == "x23");
				--------------------
		*/
		@property Char frontCodeUnit()const scope pure nothrow @trusted @nogc{
			return _all_chars[0];
		}

		/// ditto
		@property Char frontCodeUnit(const Char val)scope pure nothrow @trusted @nogc{
			return _all_chars[0] = val;
		}



		/**
			Returns last utf code point(`dchar`) of the `BasicString`.

			This function shall not be called on empty strings.

			Examples:
				--------------------
				BasicString!char str = "123á";

				assert(str.backCodePoint == 'á');
				--------------------

				--------------------
				BasicString!char str = "123á";
				str.backCodePoint = '4';
				assert(str == "1234");
				--------------------
		*/
		@property dchar backCodePoint()const scope pure nothrow @trusted @nogc{
			auto chars = _chars;

			if(chars.length == 0)
				return dchar.init;

			static if(is(Char == dchar)){
				return backCodeUnit();
			}
			else{
				const ubyte len = strideBack(chars);
				if(len == 0)
					return dchar.init;

				chars = chars[$ - len .. $];
				return decode(chars);
			}
		}

		/// ditto
		@property dchar backCodePoint()(const dchar val)scope{
			auto chars = _chars;

			static if(is(Char == dchar)){
				return backCodeUnit(val);
			}
			else{
				if(chars.length == 0)
					return dchar.init;

				const ubyte len = strideBack(chars);
				if(len == 0)
					return dchar.init;

				_length = chars.length - len;
				append(val);
				return val;
			}
		}


		/**
			Returns the last character(utf8: `char`, utf16: `wchar`, utf32: `dchar`) of the `BasicString`.

			This function shall not be called on empty strings.

			Examples:
				--------------------
				BasicString!char str = "123";

				assert(str.backCodeUnit == '3');
				--------------------

				--------------------
				BasicString!char str = "12á";

				immutable(char)[2] a = "á";
				assert(str.backCodeUnit == a[1]);
				--------------------

				--------------------
				BasicString!char str = "123";

				str.backCodeUnit = 'x';
				assert(str == "12x");
				--------------------
		*/
		@property Char backCodeUnit()const scope pure nothrow @trusted @nogc{
			auto chars = _chars;

			return chars.length == 0
				? Char.init
				: chars[$ - 1];
		}

		/// ditto
		@property Char backCodeUnit(const Char val)scope pure nothrow @trusted @nogc{
			auto chars = _chars;

			return chars.length == 0
				? Char.init
				: (chars[$ - 1] = val);
		}



		/**
			Erases the last utf code point of the `BasicString`, effectively reducing its length by code point length.

			Return number of erased characters, 0 if string is empty or if last character is not valid code point.

			Examples:
				--------------------
				BasicString!char str = "á1";    //'á' is encoded as 2 chars

				assert(str.popBackCodePoint == 1);
				assert(str == "á");

				assert(str.popBackCodePoint == 2);
				assert(str.empty);

				assert(str.popBackCodePoint == 0);
				assert(str.empty);
				--------------------

				--------------------
				BasicString!char str = "1á";    //'á' is encoded as 2 chars
				assert(str.length == 3);

				str.erase(str.length - 1);
				assert(str.length == 2);

				assert(str.popBackCodePoint == 0);   //popBackCodePoint cannot remove invalid code points
				assert(str.length == 2);
				--------------------
		*/
		ubyte popBackCodePoint()scope pure nothrow @trusted @nogc{
			if(empty)
				return 0;

			const ubyte n = strideBack(_chars);

			if(_sso)
				_short.length -= n;
			else
				_long.length -= n;

			return n;
		}



		/**
			Erases the last code unit of the `BasicString`, effectively reducing its length by 1.

			Return number of erased characters, `false` if string is empty or `true` if is not.

			Examples:
				--------------------
				BasicString!char str = "á1";    //'á' is encoded as 2 chars
				assert(str.length == 3);

				assert(str.popBackCodeUnit);
				assert(str.length == 2);

				assert(str.popBackCodeUnit);
				assert(str.length == 1);

				assert(str.popBackCodeUnit);
				assert(str.empty);

				assert(!str.popBackCodeUnit);
				assert(str.empty);
				--------------------
		*/
		bool popBackCodeUnit()scope pure nothrow @trusted @nogc{
			if(empty)
				return false;

			if(_sso)
				_short.length -= 1;
			else
				_long.length -= 1;

			return true;
		}



		/**
			Erases the contents of the `BasicString`, which becomes an empty string (with a length of 0 characters).

			Doesn't change capacity of string.

			Examples:
				--------------------
				BasicString!char str = "123";

				str.reserve(str.capacity * 2);
				assert(str.length == 3);

				in size_t cap = str.capacity;
				str.clear();
				assert(str.capacity == cap);
				--------------------
		*/
		void clear()scope pure nothrow @trusted @nogc{
			_length = 0;
		}



		/**
			Erases and deallocate the contents of the `BasicString`, which becomes an empty string (with a length of 0 characters).

			Examples:
				--------------------
				BasicString!char str = "123";

				str.reserve(str.capacity * 2);
				assert(str.length == 3);

				in size_t cap = str.capacity;
				str.clear();
				assert(str.capacity == cap);

				str.destroy();
				assert(str.capacity < cap);
				assert(str.capacity == BasicString!char.MinimalCapacity);
				--------------------
		*/
		void destroy()scope{
			if(_sso){
				_short.length = 0;
			}
			else{
				_deallocate(_long_all_chars);

				_short.setShort();
				_short.length = 0;
			}
		}



		/**
			Requests that the string capacity be adapted to a planned change in size to a length of up to n characters (utf code units).

			If n is greater than the current string capacity, the function causes the container to increase its capacity to n characters (or greater).

			In all other cases, it do nothing.

			This function has no effect on the string length and cannot alter its content.

			Examples:
				--------------------
				BasicString!char str = "123";
				assert(str.capacity == BasicString!char.MinimalCapacity);

				in size_t cap = (str.capacity * 2);
				str.reserve(cap);
				assert(str.capacity > BasicString!char.MinimalCapacity);
				assert(str.capacity >= cap);
				--------------------
		*/
		size_t reserve(in size_t n)scope{
			return _sso
				? _reserve_short(n)
				: _reserve_long(n);
		}


		private size_t _reserve_short(in size_t n)scope{
			assert(_sso);

			enum size_t old_capacity = _short.capacity;

			if(n <= old_capacity)
				return old_capacity;

			const length = _short_length;
			const new_capacity = max(old_capacity * 2, n + 1) & ~0x1;

			//assert(new_capacity >= max(old_capacity * 2, n));
			assert(new_capacity % 2 == 0);


			Char[] cdata = _allocate(new_capacity);

			()@trusted{
				_memcpy(cdata.ptr, _short_ptr, length);    //cdata[0 .. length] = _short_chars();
				assert(_chars == cdata[0 .. length]); //assert(_chars == cdata[0 .. length]);

				_long.capacity = new_capacity;
				assert(!_sso);
				_long.ptr = cdata.ptr;
				_long.length = length;
			}();

			return new_capacity;
		}

		private size_t _reserve_long(in size_t n)scope{
			assert(!_sso);

			const old_capacity = _long_capacity;

			if(n <= old_capacity)
				return old_capacity;

			const length = _long_length;
			const new_capacity = max(old_capacity * 2, n + 1) & ~0x1;

			//assert(new_capacity >= max(old_capacity * 2, n));
			assert(new_capacity % 2 == 0);

			Char[] cdata = _reallocate(_long_all_chars(), length, new_capacity);

			()@trusted{
				_long.capacity = new_capacity;
				_long.ptr = cdata.ptr;
				assert(!_sso);
			}();

			return new_capacity;

		}



		/**
			Resizes the string to a length of `n` characters (utf code units).

			If `n` is smaller than the current string length, the current value is shortened to its first `n` character, removing the characters beyond the nth.

			If `n` is greater than the current string length, the current content is extended by inserting at the end as many characters as needed to reach a size of n.

			If `ch` is specified, the new elements are initialized as copies of `ch`, otherwise, they are `_`.

			Examples:
				--------------------
				BasicString!char str = "123";

				str.resize(5, 'x');
				assert(str == "123xx");

				str.resize(2);
				assert(str == "12");
				--------------------
		*/
		void resize(in size_t n, const Char ch = '_')scope{
			const old_length = length;

			if(old_length > n){
				()@trusted{
					_length = n;
				}();
			}
			else if(old_length < n){
				append(ch, n - old_length);
			}
		}



		/**
			Requests the `BasicString` to reduce its capacity to fit its length.

			The request is non-binding.

			This function has no effect on the string length and cannot alter its content.

			Returns new capacity.

			Examples:
				--------------------
				BasicString!char str = "123";
				assert(str.capacity == BasicString!char.MinimalCapacity);

				str.reserve(str.capacity * 2);
				assert(str.capacity > BasicString!char.MinimalCapacity);

				str.shrinkToFit();
				assert(str.capacity == BasicString!char.MinimalCapacity);
				--------------------
		*/
		size_t shrinkToFit()scope{
			if(_sso)
				return MinimalCapacity;

			const old_capacity = _long_capacity;
			const length = _long_length;


			if(length == old_capacity)
				return length;

			Char[] cdata = _long_all_chars();

			if(length <= MinimalCapacity){
				//alias new_capacity = length;

				_short.setShort();
				_short.length = cast(ShortLength)length;

				()@trusted{
					_memcpy(_short_ptr, cdata.ptr, length);    //_short.data[0 .. length] = cdata[0 .. length];
				}();

				_deallocate(cdata);

				assert(_sso);
				return MinimalCapacity;
			}

			const new_capacity = (length + 1) & ~0x1;

			if(new_capacity >= old_capacity)
				return old_capacity;

			assert(new_capacity >= length);
			assert(new_capacity % 2 == 0);

			cdata = _reallocate_optional(cdata, new_capacity);

			()@trusted{
				_long.ptr = cdata.ptr;
				_long.capacity = new_capacity;
				assert(!_sso);
			}();

			return new_capacity;
		}



		/**
			Destroys the `BasicString` object.

			This deallocates all the storage capacity allocated by the `BasicString` using its allocator.
		*/
		~this()scope{
			if(!_sso){
				_deallocate(_long_all_chars());
				debug _short.setShort();
				debug _short.length = 0;
			}
		}



		/**
			Constructs a empty `BasicString` with allocator `a`.
		*/
		static if(!hasStatelessAllocator)
		this(scope return Allocator a)scope pure nothrow @safe @nogc{
			_allocator = a;
		}



		/**
			@disable init if `BasicString` has allocator with state.
		*/
		static if(!hasStatelessAllocator)
		@disable this()scope pure nothrow @trusted @nogc;



		/**
			Constructs a `BasicString` object, initializing its value to `val`.

			Parameters:
				`allocator` exists only if template parameter `_Allocator` has state.

				`val` can by type of `null`, `BasicString!(T...)`, char|wchar|dchar array/slice/character or integer (integers are transformed to string)

			Examples:
				--------------------
				{
					BasicString!char str = null;
					assert(str.empty);
				}

				{
					BasicString!char str = 'X';
					assert(str == "X");
				}

				{
					BasicString!char str = "123"w;
					assert(str == "123");
				}

				{
					BasicString!char str = 123uL;
					assert(str == "123");
				}
				--------------------
		*/
		this(scope return AllocatorWithState[0 .. $] allocator, typeof(null) val)scope pure nothrow @safe @nogc{
			assert(_sso);
			assert(capacity == Short.capacity);
			assert(_short_length == 0);

			static if(!hasStatelessAllocator)
				_allocator = allocator[0];
		}

		/// ditto
		this(scope return AllocatorWithState[0 .. $] allocator, scope const Char[] val)scope{
			this(allocator, val, Impl.init);
		}

		/// ditto
		this(Val)(scope return AllocatorWithState[0 .. $] allocator, auto ref scope const Val val)scope
		if(isBasicString!Val || isSomeChar!Val || isOtherString!Val || isCharArray!Val || isIntegral!Val){
			static if(isSmallCharArray!Val)
				this(allocator, val, Impl.init);
			else static if(isBasicString!Val)
				this(allocator, val._chars, Impl.init);
			else static if(isSomeString!Val || isCharArray!Val)
				this(allocator, val[], Impl.init);
			else static if(isSomeChar!Val || isIntegral!Val)
				this(allocator, val, Impl.init);
			else static assert(0, "invalid type '" ~ Val.stringof ~ "'");
		}

		private{
			this(C)(scope return AllocatorWithState[0 .. $] allocator, Impl)scope pure nothrow @trusted @nogc
			if(isSomeChar!C){
				assert(_sso);
				static if(!hasStatelessAllocator)
					_allocator = allocator[0];
			}

			this(C)(scope return AllocatorWithState[0 .. $] allocator, const C c, Impl)scope pure nothrow @trusted @nogc
			if(isSomeChar!C){
				assert(_sso);
				static if(!hasStatelessAllocator)
					_allocator = allocator[0];
				_short.length = cast(ShortLength)c.encodeTo(_short_all_chars);    //_short.data[0] = c;;
			}

			this(C)(scope return AllocatorWithState[0 .. $] allocator, scope const C[] str, Impl)scope
			if(isSomeChar!C){
				assert(_sso);

				static if(!hasStatelessAllocator)
					_allocator = allocator[0];

				const str_length = encodedLength(str);

				if(str_length > _short.capacity){


					const new_capacity = ((str_length + 1) & ~0x1);

					assert(new_capacity >= str_length);
					assert(new_capacity % 2 == 0);


					Char[] cdata = _allocate(new_capacity);

					()@trusted{
						_long.ptr = cdata.ptr;
						_long.length = str[].encodeTo(cdata[]);   //cdata[] = str[];
						_long.capacity = new_capacity;
					}();
					assert(!_sso);

				}
				else if(str.length != 0){
					assert(_sso);

					_short.length = cast(ShortLength)str[].encodeTo(_short_all_chars);   //_short.data[0 .. str_length] = str[];   ///str_length;
					assert(capacity == Short.capacity);
				}
				else{
					assert(_sso);
					assert(capacity == Short.capacity);
					assert(_short.length == 0);
				}

			}

			this(I)(scope return AllocatorWithState[0 .. $] allocator, I val, Impl)scope
			if(isIntegral!I){
				static if(!hasStatelessAllocator)
					_allocator = allocator[0];

				const len = encodedLength(val);

				reserve(len);
				_length = val.encodeTo(_all_chars);
			}

			this(C, size_t N)(scope return AllocatorWithState[0 .. $] allocator, scope ref const C[N] str, Impl)scope pure nothrow @trusted @nogc
			if(isSmallCharArray!(typeof(str))){
				assert(_sso);

				static if(!hasStatelessAllocator)
					_allocator = allocator[0];

				if(str.length != 0){
					assert(_sso);

					_short.length = cast(ShortLength)str[].encodeTo(_short_all_chars);   //_short.data[0 .. str_length] = str[];   ///str_length;
					assert(capacity == Short.capacity);
				}
				else{
					assert(_sso);
					assert(capacity == Short.capacity);
					assert(_short_length == 0);
				}
			}

		}

		/**
			Copy constructor if `Allocator` is statless.

			Parameter `rhs` is const.
		*/
		static if(hasStatelessAllocator)
		this(ref scope const typeof(this) rhs)scope{
			this(rhs._chars, Impl.init);
		}

		/**
			Copy constructor if `Allocator` has state.

			Parameter `rhs` is mutable.
		*/
		static if(!hasStatelessAllocator)
		this(ref scope typeof(this) rhs)scope{
			this(rhs._allocator, rhs._chars, Impl.init);
		}


		//TODO move ctor


		/**
			Assigns a new value `rhs` to the string, replacing its current contents.

			Parameter `rhs` can by type of `null`, `BasicString!(...)`, `char|wchar|dchar` array/slice/character or integer (integer is transformed to string).

			Return referece to `this`.

			Examples:
				--------------------
				BasicString!char str = "123";
				assert(!str.empty);

				str = null;
				assert(str.empty);

				str = 'X';
				assert(str == "X");

				str = "abc"w;
				assert(str == "abc");

				str = -123;
				assert(str == "-123");
				--------------------
		*/
		ref typeof(this) opAssign(typeof(null) rhs)return scope pure nothrow @safe @nogc{
			clear();
			return this;
		}

		/// ditto
		ref typeof(this) opAssign(scope const Char[] rhs)return scope{
			return _op_assign(rhs);
		}

		/// ditto
		ref typeof(this) opAssign(Val)(auto ref scope Val rhs)return scope
		if(isBasicString!Val || isSomeChar!Val || isOtherString!Val || isCharArray!Val || isIntegral!Val){

			static if(isSmallCharArray!Val)
				return _op_assign(rhs);
			else static if(isBasicString!Val)
				return _op_assign(forwardBasicString!rhs);
			else static if(isSomeString!Val || isCharArray!Val)
				return _op_assign(rhs[]);
			else static if(isSomeChar!Val || isIntegral!Val)
				return _op_assign(rhs);
			else static assert(0, "invalid type '" ~ Val.stringof ~ "'");
		}

		private{
			ref typeof(this) _op_assign(C)(const C c)return scope pure nothrow @trusted @nogc
			if(isSomeChar!C){
				clear();

				if(_sso)
					_short.length = cast(ShortLength)c.encodeTo(_short_all_chars); //_short.data[0] = c;
				else
					_long.length = c.encodeTo(_long_all_chars[0 .. dchar.sizeof / Char.sizeof]); //*_long.data = c;

				return this;
			}

			ref typeof(this) _op_assign(C)(scope const C[] str)return scope
			if(isSomeChar!C){
				clear();

				const str_length = encodedLength(str);

				if(str_length > 0){

					reserve(str_length);

					()@trusted{
						_length = str.encodeTo(_all_chars);   //_all_chars[0 .. str_length] = str[];
						assert(str_length == length);
					}();
				}

				return this;
			}

			ref typeof(this) _op_assign(I)(const I val)return scope
			if(isIntegral!I){

				clear();
				import std.conv : toChars;

				const len = encodedLength(val);
				reserve(len);

				_length = val.encodeTo(_all_chars);

				return this;
			}

			ref typeof(this) _op_assign(C, size_t N)(ref scope const C[N] str)return scope pure nothrow @trusted @nogc
			if(isSmallCharArray!(typeof(str))){
				clear();

				const str_length = str.length;	//encodedLength!Char(str);

				if(str_length > 0){
					()@trusted{
						_length = str[].encodeTo(_all_chars);   //_all_chars[0 .. str_length] = str[];
						assert(str_length == length);
					}();
				}

				return this;
			}

			ref typeof(this) _op_assign(Args...)(auto ref scope const BasicString!Args str)return scope{
				return _op_assign(str._chars);
			}

			ref typeof(this) _op_assign(ref return scope typeof(this) str)return scope {
				return _op_assign(str._chars);
			}

			ref typeof(this) _op_assign(return scope typeof(this) str)return scope{
				destroy();
				moveEmplaceImpl(str, this);
				return this;
			}
		}

		/**
			Extends the `BasicString` by appending additional characters at the end of its current value.

			Parameter `rhs` can by type of `BasicString!(...)`, `char|wchar|dchar` array/slice/character or integer (integer is transformed to string).

			Return referece to `this`.

			Examples:
				--------------------
				BasicString!char str = null;
				assert(str.empty);

				str += '1';
				assert(str == "1");

				str += "23"d;
				assert(str == "123");

				str += Str!dchar("456");
				assert(str == "123456");

				str += (+78);
				assert(str == "12345678");
				--------------------
		*/
		ref typeof(this) opOpAssign(string op : "+")(scope const Char[] rhs)return scope{
			append(rhs[]);
			return this;
		}

		/// ditto
		ref typeof(this) opOpAssign(string op : "+", Val)(auto ref scope Val rhs)return scope
		if(isBasicString!Val || isSomeChar!Val || isOtherString!Val || isCharArray!Val || isIntegral!Val){
			append(rhs);
			return this;
		}



		/**
			Returns a newly constructed `BasicString` object with its value being the concatenation of the characters in `this` followed by those of `rhs`.

			Parameter `rhs` can by type of `BasicString!(...)`, `char|wchar|dchar` array/slice/character.

			Examples:
				--------------------
				BasicString!char str = null;
				assert(str.empty);

				str = str + '1';
				assert(str == "1");

				str = str + "23"d;
				assert(str == "123");

				str = str + Str!dchar("456");
				assert(str == "123456");
				--------------------
		*/
		typeof(this) opBinary(string op : "+")(scope const Char[] rhs)scope{
			static if(hasStatelessAllocator)
				return build(_chars, rhs);
			else
				return build(_allocator, _chars, rhs);
		}

		/// ditto
		typeof(this) opBinary(string op : "+", Val)(auto ref scope const Val rhs)scope
		if(isBasicString!Val || isSomeChar!Val || isOtherString!Val || isCharArray!Val || isIntegral!Val){
			static if(isBasicString!Val){
				static if(hasStatelessAllocator)
					return build(_chars, rhs._chars);
				else
					return build(_allocator, _chars, rhs._chars);
			}
			else static if( isSomeString!Val || isCharArray!Val){
				static if(hasStatelessAllocator)
					return build(_chars, rhs[]);
				else
					return build(_allocator, _chars, rhs[]);
			}
			else static if(isSomeChar!Val || isIntegral!Val){
				static if(hasStatelessAllocator)
					return build(_chars, rhs);
				else
					return build(_allocator, _chars, rhs);

			}
			else static assert(0, "invalid type '" ~ Val.stringof ~ "'");
		}



		/**
			Returns a newly constructed `BasicString` object with its value being the concatenation of the characters in `lhs` followed by those of `this`.

			Parameter `lhs` can by type of `BasicString!(...)`, `char|wchar|dchar` array/slice/character.

			Examples:
				--------------------
				BasicString!char str = null;
				assert(str.empty);

				str = '1' + str;
				assert(str == "1");

				str = "32"d + str;
				assert(str == "321");

				str = Str!dchar("654") + str;
				assert(str == "654321");
				--------------------
		*/
		typeof(this) opBinaryRight(string op : "+")(scope const Char[] lhs)scope{
			static if(hasStatelessAllocator)
				return build(lhs, _chars);
			else
				return build(_allocator, lhs, _chars);
		}

		/// ditto
		typeof(this) opBinaryRight(string op : "+", Val)(auto ref scope const Val lhs)scope
		if(isSomeChar!Val || isOtherString!Val || isCharArray!Val || isIntegral!Val){
			static if(isSomeString!Val || isCharArray!Val){
				static if(hasStatelessAllocator)
					return build(lhs[], _chars);
				else
					return build(_allocator, lhs[], _chars);
			}
			else static if(isSomeChar!Val || isIntegral!Val){
				static if(hasStatelessAllocator)
					return build(lhs, _chars);
				else
					return build(_allocator, lhs, _chars);
			}
			else static assert(0, "invalid type '" ~ Val.stringof ~ "'");
		}



		/**
			Calculates the hash value of string.
		*/
		size_t toHash()const pure nothrow @safe @nogc{
			return hashOf(_chars);
		}



		/**
			Compares the contents of a string with another string, range, char/wchar/dchar or integer.

			Returns `true` if they are equal, `false` otherwise

			Examples:
				--------------------
				BasicString!char str = "123";

				assert(str == "123");
				assert("123" == str);

				assert(str == "123"w);
				assert("123"w == str);

				assert(str == "123"d);
				assert("123"d == str);

				assert(str == BasicString!wchar("123"));
				assert(BasicString!wchar("123") == str);

				assert(str == 123);
				assert(123 == str);

				import std.range : only;
				assert(str == only('1', '2', '3'));
				assert(only('1', '2', '3') == str);
				--------------------
		*/
		bool opEquals(scope const Char[] rhs)const scope pure nothrow @safe @nogc{
			return _op_equals(rhs[]);
		}

		/// ditto
		bool opEquals(Val)(auto ref scope Val rhs)const scope
		if(isBasicString!Val || isSomeChar!Val || isOtherString!Val || isCharArray!Val || isIntegral!Val || isInputCharRange!Val){
			static if(isBasicString!Val)
				return _op_equals(rhs._chars);
			else static if(isSomeString!Val || isCharArray!Val)
				return _op_equals(rhs[]);
			else static if(isSomeChar!Val){
				import std.range : only;
				return _op_equals(only(rhs));
			}
			else static if(isIntegral!Val){
				import std.conv : toChars;
				return _op_equals(toChars(rhs + 0));
			}
			else static if(isInputRange!Val)
				return _op_equals(rhs);
			else static assert(0, "invalid type '" ~ Val.stringof ~ "'");
		}


		private bool _op_equals(Range)(auto ref scope Range rhs)const scope
		if(isInputCharRange!Range){
			import std.range : empty, hasLength;

			alias RhsChar = Unqual!(ElementEncodingType!Range);
			auto lhs = _chars;

			enum lengthComperable = hasLength!Range && is(Unqual!Char == RhsChar);

			static if(lengthComperable){
				if(lhs.length != rhs.length)
					return false;
			}
			/+TODO: else static if(hasLength!Range){
				static if(Char.sizeof < RhsChar.sizeof){
					if(lhs.length * (RhsChar.sizeof / Char.sizeof) < rhs.length)
						return false;
				}
				else static if(Char.sizeof > RhsChar.sizeof){
					if(lhs.length > rhs.length * (Char.sizeof / RhsChar.sizeof))
						return false;

				}
				else static assert(0, "no impl")
			}+/

			while(true){
				static if(lengthComperable){
					if(lhs.length == 0){
						assert(rhs.empty);
						return true;
					}
				}
				else{
					if(lhs.length == 0)
						return rhs.empty;

					if(rhs.empty)
						return false;
				}

				static if(is(Unqual!Char == RhsChar)){

					const a = lhs.frontCodeUnit;
					lhs.popFrontCodeUnit();

					const b = rhs.frontCodeUnit;
					rhs.popFrontCodeUnit();

					static assert(is(Unqual!(typeof(a)) == Unqual!(typeof(b))));
				}
				else{
					const a = decode(lhs);
					const b = decode(rhs);
				}

				if(a != b)
					return false;

			}
		}



		/**
			Compares the contents of a string with another string, range, char/wchar/dchar or integer.
		*/
		int opCmp(scope const Char[] rhs)const scope pure nothrow @safe @nogc{
			import std.algorithm.comparison : cmp;

			//return cmp(this[], rhs[]);
			return _op_cmp(rhs[]);
		}

		/// ditto
		int opCmp(Val)(auto ref scope Val rhs)const scope
		if(isBasicString!Val || isSomeChar!Val || isOtherString!Val || isCharArray!Val || isIntegral!Val || isInputCharRange!Val){

			static if(isBasicString!Val)
				return _op_cmp(rhs._chars);
			else static if(isSomeString!Val || isCharArray!Val)
				return _op_cmp(rhs[]);
			else static if(isSomeChar!Val){
				import std.range : only;
				return _op_cmp(only(rhs));
			}
			else static if(isIntegral!Val){
				import std.conv : toChars;
				return _op_cmp(toChars(rhs + 0));
			}
			else static if(isInputRange!Val)
				return _op_cmp(val);
			else static assert(0, "invalid type '" ~ Val.stringof ~ "'");
		}


		private int _op_cmp(Range)(Range rhs)const scope
		if(isInputCharRange!Range){
			import std.range : empty;

			auto lhs = _chars;
			alias RhsChar = Unqual!(ElementEncodingType!Range);

			while(true){
				if(lhs.empty)
					return rhs.empty ? 0 : -1;

				if(rhs.empty)
					return 1;

				static if(is(Unqual!Char == RhsChar)){

					const a = lhs.frontCodeUnit;
					lhs.popFrontCodeUnit();

					const b = rhs.frontCodeUnit;
					rhs.popFrontCodeUnit();

					static assert(is(Unqual!(typeof(a)) == Unqual!(typeof(b))));
				}
				else{
					const a = decode(lhs);
					const b = decode(rhs);
				}

				if(a < b)
					return -1;

				if(a > b)
					return 1;
			}
		}



		/**
			Return slice of all character.

			The slice returned may be invalidated by further calls to other member functions that modify the object.

			Examples:
				--------------------
				BasicString!char str = "123";

				char[] slice = str[];
				assert(slice.length == str.length);
				assert(slice.ptr is str.ptr);

				str.reserve(str.capacity * 2);
				assert(slice.length == str.length);
				assert(slice.ptr !is str.ptr);  // slice contains dangling pointer.
				--------------------
		*/
		inout(Char)[] opSlice()inout scope return pure nothrow @system @nogc{
			return _chars;
		}

		/**
			Returns a slice [begin .. end]. If the requested substring extends past the end of the string, the returned slice is [begin .. length()].

			The slice returned may be invalidated by further calls to other member functions that modify the object.

			Examples:
				--------------------
				BasicString!char str = "123456";

				assert(str[1 .. $-1] == "2345");
				--------------------
		*/
		inout(Char)[] opSlice(size_t begin, size_t end)inout return pure nothrow @system @nogc{
			begin = min(length, begin);
			end = min(length, end);

			return _sso ? _short.data[begin .. end] : _long.ptr[begin .. end];
		}


		/**
			Returns character at specified location `pos`.

			Examples:
				--------------------
				BasicString!char str = "abcd";

				assert(str[1] == 'b');
				--------------------
		*/
		Char opIndex(in size_t pos)const scope pure nothrow @trusted @nogc{
			assert(0 <= pos && pos < length, "error");

			return _sso
				? _short.data[pos]
				: *(_long.ptr + pos);
		}



		/**
			Assign character at specified location `pos` to value `val`.

			Returns 'val'.

			Examples:
				--------------------
				BasicString!char str = "abcd";

				str[1] = 'x';

				assert(str == "axcd");
				--------------------
		*/
		Char opIndexAssign(const Char val, in size_t pos)scope pure nothrow @trusted @nogc{
			assert(0 <= pos && pos < length, "error");

			if(_sso)
				_short.data[pos] = val;
			else
				*(_long.ptr + pos) = val;

			return val;
		}



		/**
			Returns the length of the string, in terms of number of characters.

			Same as `length()`.
		*/
		size_t opDollar()const scope pure nothrow @safe @nogc{
			return length;
		}



		/**
			Swaps the contents of `this` and `rhs`.

			Examples:
				--------------------
				BasicString!char a = "1";
				BasicString!char b = "2";

				a.proxySwap(b);
				assert(a == "2");
				assert(b == "1");

				import std.algorithm.mutation : swap;

				swap(a, b);
				assert(a == "1");
				assert(b == "2");
				--------------------
		*/
		void proxySwap(ref scope typeof(this) rhs)scope pure nothrow @trusted @nogc{
			import std.algorithm.mutation : swap;
			swap(_raw, rhs._raw);

			static if(!hasStatelessAllocator)
				swap(_allocator, rhs._allocator);
		}



		/**
			Extends the `BasicString` by appending additional characters at the end of string.

			Return number of inserted characters.

			Parameters:
				`val` appended value.

				`count` Number of times `val` is appended.

			Examples:
				--------------------
				BasicString!char str = "123456";

				str.append('x', 2);
				assert(str == "123456xx");
				--------------------

				--------------------
				BasicString!char str = "123456";

				str.append("abc");
				assert(str == "123456abc");
				--------------------

				--------------------
				BasicString!char str = "123456";
				BasicString!char str2 = "xyz";

				str.append(str2);
				assert(str == "123456xyz");
				--------------------

				--------------------
				BasicString!char str = "12";

				str.append(+34);
				assert(str == "1234");
				--------------------
		*/
		size_t append(const Char[] val, in size_t count = 1)scope{
			return _append_impl(val, count);
		}

		/// ditto
		size_t append(Val)(auto ref scope const Val val, in size_t count = 1)scope
		if(isBasicString!Val || isSomeChar!Val || isOtherString!Val || isCharArray!Val || isIntegral!Val){

			static if(isBasicString!Val)
				return _append_impl(val._chars, count);
			else static if(isSomeString!Val || isCharArray!Val)
				return _append_impl(val[], count);
			else static if(isSomeChar!Val || isIntegral!Val)
				return _append_impl(val, count);
			else static assert(0, "invalid type '" ~ Val.stringof ~ "'");
		}


		private size_t _append_impl(Val)(const Val val, in size_t count)scope
		if(isSomeChar!Val || isSomeString!Val || isIntegral!Val){
			if(count == 0)
				return 0;

			const old_length = length;
			const new_count = count * encodedLength(val);

			Char[] new_chars = _expand(new_count);
			const tmp = val.encodeTo(new_chars, count);
			assert(tmp == new_count);
			return tmp;
		}



		/**
			Inserts additional characters into the `BasicString` right before the character indicated by `pos` or `ptr`.

			Return number of inserted characters.

			If parameters are out of range then there is no inserted value and in debug mode assert throw error.

			Parameters are out of range if `pos` is larger then `.length` or `ptr` is smaller then `ptr` or `ptr` point to address larger then `ptr + length`

			Parameters:
				`pos` Insertion point, the new contents are inserted before the character at position `pos`.

				`ptr` Pointer pointing to the insertion point, the new contents are inserted before the character pointed by ptr.

				`val` Value inserted before insertion point `pos` or `ptr`.

				`count` Number of times `val` is inserted.

			Examples:
				--------------------
				BasicString!char str = "123456";

				str.insert(2, 'x', 2);
				assert(str == "12xx3456");
				--------------------

				--------------------
				BasicString!char str = "123456";

				str.insert(2, "abc");
				assert(str == "12abc3456");
				--------------------

				--------------------
				BasicString!char str = "123456";
				BasicString!char str2 = "abc";

				str.insert(2, str2);
				assert(str == "12abc3456");
				--------------------


				--------------------
				BasicString!char str = "123456";

				str.insert(str.ptr + 2, 'x', 2);
				assert(str == "12xx3456");
				--------------------

				--------------------
				BasicString!char str = "123456";

				str.insert(str.ptr + 2, "abc");
				assert(str == "12abc3456");
				--------------------

				--------------------
				BasicString!char str = "123456";
				BasicString!char str2 = "abc";

				str.insert(str.ptr + 2, str2);
				assert(str == "12abc3456");
				--------------------

		*/
		size_t insert(in size_t pos, const scope Char[] val, in size_t count = 1)scope{
			return _insert_impl(pos, val, count);
		}

		/// ditto
		size_t insert(Val)(in size_t pos, auto ref const scope Val val, in size_t count = 1)scope
		if(isBasicString!Val || isSomeChar!Val || isOtherString!Val || isIntegral!Val){
			static if(isBasicString!Val || isSomeString!Val)
				return _insert_impl(pos, val[], count);
			else static if(isSomeChar!Val || isIntegral!Val)
				return _insert_impl(pos, val, count);
			else static assert(0, "invalid type '" ~ Val.stringof ~ "'");
		}

		/// ditto
		size_t insert(const Char* ptr, const scope Char[] val, in size_t count = 1)scope{
			const pos = _insert_ptr_to_pos(ptr);

			return _insert_impl(pos, val, count);
		}

		/// ditto
		size_t insert(Val)(const Char* ptr, auto ref const scope Val val, in size_t count = 1)scope
		if(isBasicString!Val || isSomeChar!Val || isOtherString!Val || isIntegral!Val){
			const pos = _insert_ptr_to_pos(ptr);

			static if(isBasicString!Val || isSomeString!Val)
				return _insert_impl(pos, val[], count);
			else static if(isSomeChar!Val || isIntegral!Val)
				return _insert_impl(pos, val, count);
			else static assert(0, "invalid type '" ~ Val.stringof ~ "'");
		}


		private size_t _insert_ptr_to_pos(const Char* ptr)scope const pure nothrow @trusted @nogc{
			const chars = _chars;

			return ptr > chars.ptr
				? ptr - chars.ptr
				: 0;
		}

		private size_t _insert_impl(Val)(in size_t pos, const Val val, in size_t count)scope
		if(isSomeChar!Val || isSomeString!Val || isIntegral!I){

			const new_count = count * encodedLength(val);
			if(new_count == 0)
				return 0;

			//auto chars = _chars;

			Char[] new_chars = _expand_move(pos, new_count);

			return val.encodeTo(new_chars, count);
		}



		/**
			Removes specified characters from the string.

			Parameters:
				`pos` position of first character to be removed.

				`n` number of character to be removed.

				`ptr` pointer to character to be removed.

				`slice` sub-slice to be removed, `slice` must be subset of `this`

			Examples:
				--------------------
				BasicString!char str = "123456";

				str.erase(2);
				assert(str == "12456");
				--------------------

				--------------------
				BasicString!char str = "123456";

				str.erase(1, 2);
				assert(str == "23");
				--------------------

				--------------------
				BasicString!char str = "123456";

				str.erase(str.ptr + 2);
				assert(str == "12456");
				--------------------

				--------------------
				BasicString!char str = "123456";

				str.erase(str[1 .. $-1]);
				assert(str == "2345");
				--------------------
		*/
		void erase(in size_t pos)scope pure nothrow @trusted @nogc{
			_length = min(length, pos);
		}

		/// ditto
		void erase(in size_t pos, in size_t n)scope pure nothrow @trusted @nogc{
			const chars = _chars;

			if(pos >= chars.length)
				return;

			const top = pos + n;

			if(top >= chars.length)
				_length = pos;
			else if(n != 0)
				_reduce_move(top, n);
		}

		/// ditto
		void erase(scope const Char* ptr)scope pure nothrow @trusted @nogc{
			const chars = _chars;

			if(ptr <= chars.ptr)
				_length = 0;
			else
				_length = min(chars.length, ptr - chars.ptr);
		}

		/// ditto
		void erase(scope const Char[] slice)scope pure nothrow @trusted @nogc{
			const chars = _chars;

			if(slice.ptr <= chars.ptr){
				const offset = chars.ptr - slice.ptr;

				if(slice.length <= offset)
					return;

				enum size_t pos = 0;


				const len = slice.length - offset;
				const top = pos + len;   //alias top = len;

				if(top >= chars.length)
					_length = pos;
				else
					_reduce_move(top, len);
			}
			else{
				const offset = (slice.ptr - chars.ptr);

				if(chars.length <= offset)
					return;

				alias pos = offset;

				const len = slice.length;
				const top = pos + len;

				if(top >= chars.length)
					_length = pos;
				else if(len != 0)
					_reduce_move(top, len);

			}
		}


		/**
			Replaces the portion of the string that begins at character `pos` and spans `len` characters (or the part of the string in the slice `slice`) by new contents.

			Parameters:
				`pos` position of the first character to be replaced.

				`len` number of characters to replace (if the string is shorter, as many characters as possible are replaced).

				`slice` sub-slice to be removed, `slice` must be subset of `this`

				`val` inserted value.

				`count` number of times `val` is inserted.

			Examples:
				--------------------
				BasicString!char str = "123456";

				str.replace(2, 2, 'x', 5);
				assert(str == "12xxxxx56");
				--------------------

				--------------------
				BasicString!char str = "123456";

				str.replace(2, 2, "abcdef");
				assert(str == "12abcdef56");
				--------------------

				--------------------
				BasicString!char str = "123456";
				BasicString!char str2 = "xy";

				str.replace(2, 3, str2);
				writeln(str[]);
				assert(str == "12xy56");
				--------------------


				--------------------
				BasicString!char str = "123456";

				str.replace(str[2 .. 4], 'x', 5);
				assert(str == "12xxxxx56");
				--------------------

				--------------------
				BasicString!char str = "123456";

				str.replace(str[2 .. 4], "abcdef");
				assert(str == "12abcdef56");
				--------------------

				--------------------
				BasicString!char str = "123456";
				BasicString!char str2 = "xy";

				str.replace(str[2 .. $], str2);
				assert(str == "12xy56");
				--------------------
		*/
		ref typeof(this) replace(in size_t pos, in size_t len, scope const Char[] val, in size_t count = 1)return scope{
			return _replace_impl(pos, len, val, count);
		}

		/// ditto
		ref typeof(this) replace(Val)(in size_t pos, in size_t len, auto ref scope const Val val, in size_t count = 1)return scope
		if(isBasicString!Val || isSomeChar!Val || isOtherString!Val || isIntegral!Val || isCharArray!Val){

			static if(isBasicString!Val || isSomeString!Val || isCharArray!Val)
				return _replace_impl(pos, len, val[], count);
			else static if(isSomeChar!Val || isIntegral!Val)
				return _replace_impl(pos, len, val, count);
			else static assert(0, "invalid type '" ~ Val.stringof ~ "'");
		}

		/// ditto
		ref typeof(this) replace(scope const Char[] slice, scope const Char[] val, in size_t count = 1)return scope{
			return _replace_impl(slice, val, count);
		}

		/// ditto
		ref typeof(this) replace(Val)(scope const Char[] slice, auto ref scope const Val val, in size_t count = 1)return scope
		if(isBasicString!Val || isSomeChar!Val || isOtherString!Val || isIntegral!Val || isCharArray!Val){

			static if(isBasicString!Val || isSomeString!Val || isCharArray!Val)
				return _replace_impl(slice, val[], count);
			else static if(isSomeChar!Val || isIntegral!Val)
				return _replace_impl(slice, val, count);
			else static assert(0, "invalid type '" ~ Val.stringof ~ "'");
		}


		private ref typeof(this) _replace_impl(Val)(scope const Char[] slice, scope const Val val, in size_t count)return scope
		if(isSomeChar!Val || isSomeString!Val || isIntegral!Val){
			const chars = _chars;

			if(slice.ptr < chars.ptr){
				const offset = (()@trusted => chars.ptr - slice.ptr)();
				const pos = 0;
				const len = slice.length > offset
					? slice.length - offset
					: 0;

				return _replace_impl(pos, len, val, count);
			}
			else{
				const offset = (()@trusted => slice.ptr - chars.ptr)();
				const pos = offset;
				const len = slice.length;

				return _replace_impl(pos, len, val, count);
			}
		}

		private ref typeof(this) _replace_impl(Val)(in size_t pos, in size_t len, scope const Val val, in size_t count)return scope
		if(isSomeChar!Val || isSomeString!Val || isIntegral!Val){

			const new_count = count * encodedLength(val);
			if(new_count == 0){
				erase(pos, len);
				return this;
			}

			assert(new_count != 0);

			auto chars = _chars;
			const old_length = chars.length;
			const begin = min(pos, chars.length);    //alias begin = pos;

			const end = min(chars.length, pos + len);
			const new_len = min(end - begin, new_count);
			//const new_len = min(len, new_count);
			//const end = (begin + new_len);


			if(begin == end){
				///insert:
				Char[] new_chars = _expand_move(begin, new_count);
				const x = val.encodeTo(new_chars, count);
				assert(x == new_count);

			}
			else if(new_count == new_len){
				///exact assign:
				const x = val.encodeTo(chars[begin .. end], count);
				assert(x == new_count);
			}
			else if(new_count < new_len){
				///asign + erase:
				const x = val.encodeTo(chars[begin .. end], count);
				assert(x == new_count);

				()@trusted{
					_reduce_move(end, new_len - new_count);
				}();
			}
			else{
				///asing + expand(insert):
				assert(new_count > new_len);

				const expand_len = new_count - new_len;

				Char[] new_chars = _expand_move(end, expand_len);

				const x = val.encodeTo((()@trusted => (new_chars.ptr - new_len)[0 .. new_count])(), count);
				assert(x == new_count);
			}

			return this;
		}



		///Alias to append.
		alias put = append;

		///Alias to `popBackCodeUnit`.
		alias popBack = popBackCodeUnit;

		///Alias to `frontCodeUnit`.
		alias front = frontCodeUnit;

		///Alias to `backCodeUnit`.
		alias back = backCodeUnit;


		/**
			Static function which return `BasicString` construct from arguments `args`.

			Parameters:
				`allocator` exists only if template parameter `_Allocator` has state.

				`args` values of type `char|wchar|dchar` array/slice/character or `BasicString`.

			Examples:
				--------------------
				BasicString!char str = BasicString!char.build('1', cast(dchar)'2', "345"d, BasicString!wchar("678"));

				assert(str == "12345678");
				--------------------
		*/
		static typeof(this) build(Args...)(scope return AllocatorWithState[0 .. $] allocator, auto ref scope const Args args){
			import core.lifetime : forward;

			static if(hasStatelessAllocator)
				auto result = BasicString.init;
			else
				auto result = (()@trusted => BasicString(allocator[0]))();

			result._build_impl(forwardBasicString!args);

			return (()@trusted => result)();
		}

		private void _build_impl(Args...)(auto ref scope const Args args)scope{
			import std.traits : isArray;

			assert(empty);
			//clear();
			size_t new_length = 0;

			static foreach(I, alias Arg; Args){
				static if(isBasicString!Arg)
					new_length += encodedLength(args[I]._chars);
				else static if(isArray!Arg && isSomeChar!(ElementEncodingType!Arg))
					new_length += encodedLength(args[I][]);
				else static if(isSomeChar!Arg)
					new_length += encodedLength(args[I]);
				else static assert(0, "wrong type '" ~ typeof(args[I]).stringof ~ "'");
			}

			if(new_length == 0)
				return;


			alias result = this;

			result.reserve(new_length);



			Char[] data = result._all_chars;

			static foreach(I, alias Arg; Args){
				static if(isBasicString!Arg)
					data = data[args[I]._chars.encodeTo(data) .. $];
				else static if(isArray!Arg)
					data = data[args[I][].encodeTo(data) .. $];
				else static if(isSomeChar!Arg)
					data = data[args[I].encodeTo(data) .. $];
				else static assert(0, "wrong type '" ~ Arg.stringof ~ "'");
			}

			()@trusted{
				result._length = new_length;
			}();
		}


		/*
		*/
		private static void moveEmplaceImpl(ref typeof(this) source, ref typeof(this) target)@trusted pure nothrow @nogc{
			//  Unsafe when compiling without -dip1000
			assert(&source !is &target, "source and target must not be identical");

			()@trusted{
				static if(hasStatelessAllocator == false)
					target._allocator = source._allocator;


				_memcpy(target._raw.ptr, source._raw.ptr, _raw.length); //target._raw[] = source._raw[];
				source._short.setShort();
				source._short.length = 0;
			}();
		}
	}


	private{
		size_t encodedLength(From)(const scope From from)pure nothrow @nogc @safe
		if(isSomeChar!From){
			return codeLength!_Char(from);
		}

		size_t encodedLength(From)(scope const(From)[] from)pure nothrow @nogc @safe
		if(isSomeChar!From){
			static if(_Char.sizeof == From.sizeof){
				return from.length;
			}
			else static if(_Char.sizeof < From.sizeof){
				size_t result = 0;

				foreach(const From c; from[]){
					result += c.encodedLength;
				}

				return result;
			}
			else{
				static assert(_Char.sizeof > From.sizeof);

				size_t result = 0;

				while(from.length){
					result += decode(from).encodedLength;
				}

				return result;
			}

		}

		size_t encodedLength(From)(const From from)pure nothrow @nogc @safe
		if(isIntegral!From){
			import std.math : log10, abs;

			if(from == 0)
				return 1;

			return cast(int)(log10(abs(from)) + 1) + (from < 0 ? 1 : 0);
		}



		size_t encodeTo(From)(scope const(From)[] from, scope _Char[] to, in size_t count = 1)pure nothrow @nogc
		if(isSomeChar!From){

			if(count == 0)
				return 0;

			assert(from.encodedLength * count <= to.length);

			debug const predictedEncodedLength = encodedLength(from);

			static if(_Char.sizeof == From.sizeof){

				const len = from.length;
				()@trusted{
					assert(to.length >= len);
					assert(from.length <= len);
					_memcpy(to.ptr, from.ptr, len); //to[0 .. len] = from[];
				}();

			}
			else{

				size_t len = 0;
				while(from.length){
					len += decode(from).encode(to[len .. $]);
				}
			}

			debug assert(predictedEncodedLength == len);

			for(size_t i = 1; i < count; ++i){
				//to[len .. len * 2] = to[0 .. len];
				()@trusted{
					assert(to.length >= (len * 2));
					_memcpy(to.ptr + len, to.ptr, len); //to[0 .. len] = from[];
				}();
				to = to[len .. $];
			}

			return len * count;
		}

		size_t encodeTo(From)(const From from, scope _Char[] to, in size_t count = 1)pure nothrow @nogc
		if(isSomeChar!From){

			if(count == 0)
				return 0;

			assert(from.encodedLength * count <= to.length);

			debug const predictedEncodedLength = encodedLength(from);

			static if(_Char.sizeof == From.sizeof){
				enum size_t len = 1;

				assert(count <= to.length);
				for(size_t i = 0; i < count; ++i){
					to[i] = from;
				}
			}
			else{
				const len = dchar(from).encode(to[]);

				for(size_t i = 1; i < count; ++i){
					//to[len .. len * 2] = to[0 .. len];
					()@trusted{
						assert(to.length >= len * 2);
						_memcpy(to.ptr + len, to.ptr, len); //to[0 .. len] = from[];
					}();
					to = to[len .. $];
				}

				assert(encodedLength(from) == len);
			}

			debug assert(predictedEncodedLength == len);

			return len * count;
		}

		size_t encodeTo(From)(const From from, scope _Char[] to, in size_t count = 1)pure nothrow @nogc
		if(isIntegral!From){
			import std.conv : toChars;

			if(count == 0)
				return 0;

			auto ichars = toChars(from + 0);

			assert(encodedLength(from) == ichars.length);

			for(size_t c = 0; c < count; ++c){
				for(size_t i = 0; i < ichars.length; ++i)
					to[c+i] = ichars[i];
			}

			return ichars.length * count;
		}

	}
}

private{
	template isInputCharRange(T){
		import std.range : isInputRange, ElementEncodingType;
		import std.traits : isArray;

		enum bool isInputCharRange = true
			&& isSomeChar!(ElementEncodingType!T)
			&& (isInputRange!T || isArray!T);
	}

	//min/max:
	version(D_BetterC){

		private auto min(A, B)(auto ref A a, auto ref B b){
			return a < b ? a : b;
		}
		private auto max(A, B)(auto ref A a, auto ref B b){
			return a > b ? a : b;
		}
	}
	else{
		import std.algorithm.comparison : min, max;
	}


	auto frontCodeUnit(Range)(auto ref Range r){
		import std.traits : isAutodecodableString;


		static if(isAutodecodableString!Range){
			assert(r.length > 0);
			return r[0];
		}
		else{
			import std.range.primitives : front;
			return r.front;
		}
	}

	void popFrontCodeUnit(Range)(ref Range r){
		import std.traits : isAutodecodableString;

		static if(isAutodecodableString!Range){
			assert(r.length > 0);
			r = r[1 .. $];
		}
		else{
			import std.range.primitives : popFront;
			return r.popFront;
		}
	}


	T moveBasicString(T)(scope return ref T source)@trusted nothrow
	if(isBasicString!T){
		T result = void;
		T.moveEmplaceImpl(source, result);
		return (()@system => result)();
	}

	template forwardBasicString(args...){
		import core.internal.traits : AliasSeq;

		static if (args.length)
		{
			alias arg = args[0];

			static if(isBasicString!(typeof(arg))){
				// by ref || lazy || const/immutable
				static if (__traits(isRef, arg) ||
						   __traits(isOut, arg) ||
						   __traits(isLazy, arg) ||
						   !is(typeof(moveBasicString(arg))))
					alias fwd = arg;
				// (r)value
				else
					@property typeof(arg) fwd()()@trusted{ return moveBasicString(arg); }

				static if (args.length == 1)
					alias forwardBasicString = fwd;
				else
					alias forwardBasicString = AliasSeq!(fwd, forwardBasicString!(args[1..$]));
			}
			else{
				import core.lifetime : forward;

				static if (args.length == 1)
					alias forwardBasicString = forward!arg;
				else
					alias forwardBasicString = AliasSeq!(forward!arg, forwardBasicString!(args[1..$]));
			}
		}
		else
			alias forwardBasicString = AliasSeq!();
	}
}