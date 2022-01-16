/**
	Mutable @nogc @safe string struct using `std.experimental.allocator` for allocations.

	License:   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
	Authors:   $(HTTP github.com/submada/basic_string, Adam Búš)
*/
module basic_string;

import std.traits : Unqual, Unconst, isSomeChar, isSomeString;
import std.meta : AliasSeq;

import basic_string.internal.mallocator;
import basic_string.internal.encoding;
import basic_string.internal.traits;
import basic_string.core;

debug import std.stdio : writeln;

/**
	True if `T` is a `BasicString` or implicitly converts to one, otherwise false.
*/
template isBasicString(T...)
if(T.length == 1){
	enum bool isBasicString = is(Unqual!(T[0]) == BasicString!Args, Args...);
}



/**
	Standard utf-8 string type (alias to `BasicString!char`).
*/
alias String = BasicString!char;




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
	import std.experimental.allocator.common :  stateSize;
	import std.range : isInputRange, ElementEncodingType, isRandomAccessRange;
	import std.traits : Unqual, isIntegral, hasMember, isArray, isSafe;
	import core.lifetime: forward, move;


	alias Core = BasicStringCore!(_Char, _Allocator, _Padding);

	struct BasicString{
		private Core core;

		/**
			True if allocator doesn't have state.
		*/
		public enum bool hasStatelessAllocator = Core.hasStatelessAllocator;



		/**
			Character type. (`char`, `wchar` or  `dchar`).
		*/
		public alias Char = Core.Char;



		/**
			Type of the allocator object used to define the storage allocation model. By default Mallocator is used.
		*/
		public alias Allocator = Core.Allocator;



		/**
			Maximal capacity of string, in terms of number of characters (utf code units).
		*/
		public alias MaximalCapacity = Core.MaximalCapacity;



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
		public alias MinimalCapacity = Core.MinimalCapacity;



		/**
			Returns allocator.
		*/
		static if(hasStatelessAllocator)
			public alias allocator = Core.allocator;
		else
			public @property auto allocator()inout{
				return this.core.allocator;
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
		public @property bool empty()const scope pure nothrow @safe @nogc{
			return (this.length == 0);
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
		public @property size_t length()const scope pure nothrow @trusted @nogc{
			return this.core.length();
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
		public @property size_t capacity()const scope pure nothrow @trusted @nogc{
			return this.core.capacity;
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
		public @property inout(Char)* ptr()inout return pure nothrow @system @nogc{
			return this.core.ptr;
		}



		/**
			Return `true` if string is small (Small String Optimization)
		*/
		public @property bool small()const scope pure nothrow @safe @nogc{
			return this.core.small;
		}



		/**
			Return `true` if string is valid utf string.
		*/
		public @property bool valid()const scope pure nothrow @safe @nogc{
			return validate(this.core.chars);
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
		public @property dchar frontCodePoint()const scope pure nothrow @trusted @nogc{
			auto chars = this.core.allChars;
			return decode(chars);
		}



		/**
			Returns the first character(utf8: `char`, utf16: `wchar`, utf32: `dchar`) of the `BasicString`.

			This function shall not be called on empty strings.

			Examples:
				--------------------
                {
				    BasicString!char str = "123";

				    assert(str.frontCodeUnit == '1');
                }

                {
				    BasicString!char str = "á23";

				    immutable(char)[2] a = "á";
				    assert(str.frontCodeUnit == a[0]);
                }

                {
				    BasicString!char str = "123";

				    str.frontCodeUnit = 'x';

				    assert(str == "x23");
                }
				--------------------
		*/
		public @property Char frontCodeUnit()const scope pure nothrow @trusted @nogc{
			return *this.ptr;
		}

		/// ditto
		public @property Char frontCodeUnit(const Char val)scope pure nothrow @trusted @nogc{
			return *this.ptr = val;
		}



		/**
			Returns last utf code point(`dchar`) of the `BasicString`.

			This function shall not be called on empty strings.

			Examples:
				--------------------
                {
				    BasicString!char str = "123á";

				    assert(str.backCodePoint == 'á');
                }

                {
				    BasicString!char str = "123á";
				    str.backCodePoint = '4';
				    assert(str == "1234");
                }
				--------------------
		*/
		public @property dchar backCodePoint()const scope pure nothrow @trusted @nogc{
			auto chars = this.core.chars;

			if(chars.length == 0)
				return dchar.init;

			static if(is(Char == dchar)){
				return this.backCodeUnit();
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
		public @property dchar backCodePoint()(const dchar val)scope{
			auto chars = this.core.chars;

			static if(is(Char == dchar)){
				return this.backCodeUnit(val);
			}
			else{
				if(chars.length == 0)
					return dchar.init;

				const ubyte len = strideBack(chars);
				if(len == 0)
					return dchar.init;

				()@trusted{
					this.length = (chars.length - len);
				}();
				this.append(val);
				return val;
			}
		}


		/**
			Returns the last character(utf8: `char`, utf16: `wchar`, utf32: `dchar`) of the `BasicString`.

			This function shall not be called on empty strings.

			Examples:
				--------------------
                {
				    BasicString!char str = "123";

				    assert(str.backCodeUnit == '3');
                }

                {
				    BasicString!char str = "12á";

				    immutable(char)[2] a = "á";
				    assert(str.backCodeUnit == a[1]);
                }

                {
				    BasicString!char str = "123";

				    str.backCodeUnit = 'x';
				    assert(str == "12x");
                }
				--------------------
		*/
		public @property Char backCodeUnit()const scope pure nothrow @trusted @nogc{
			auto chars = this.core.chars;

			return (chars.length == 0)
				? Char.init
				: chars[$ - 1];
		}

		/// ditto
		public @property Char backCodeUnit(const Char val)scope pure nothrow @trusted @nogc{
			auto chars = this.core.chars;

			return (chars.length == 0)
				? Char.init
				: (chars[$ - 1] = val);
		}



		/**
			Erases the last utf code point of the `BasicString`, effectively reducing its length by code point length.

			Return number of erased characters, 0 if string is empty or if last character is not valid code point.

			Examples:
				--------------------
                {
				    BasicString!char str = "á1";    //'á' is encoded as 2 chars

				    assert(str.popBackCodePoint == 1);
				    assert(str == "á");

				    assert(str.popBackCodePoint == 2);
				    assert(str.empty);

				    assert(str.popBackCodePoint == 0);
				    assert(str.empty);
                }

                {
				    BasicString!char str = "1á";    //'á' is encoded as 2 chars
				    assert(str.length == 3);

				    str.erase(str.length - 1);
				    assert(str.length == 2);

				    assert(str.popBackCodePoint == 0);   //popBackCodePoint cannot remove invalid code points
				    assert(str.length == 2);
                }
				--------------------
		*/
		public ubyte popBackCodePoint()scope pure nothrow @trusted @nogc{
			if(this.empty)
				return 0;

			const ubyte n = strideBack(this.core.chars);

			this.core.length = (this.length - n);

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
		public bool popBackCodeUnit()scope pure nothrow @trusted @nogc{
			if(this.empty)
				return false;

			this.core.length = (this.length - 1);

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

				const size_t cap = str.capacity;
				str.clear();
				assert(str.capacity == cap);
				--------------------
		*/
		public void clear()scope pure nothrow @trusted @nogc{
			this.core.length = 0;
		}



		/**
			Erases and deallocate the contents of the `BasicString`, which becomes an empty string (with a length of 0 characters).

			Examples:
				--------------------
				BasicString!char str = "123";

				str.reserve(str.capacity * 2);
				assert(str.length == 3);

				const size_t cap = str.capacity;
				str.clear();
				assert(str.capacity == cap);

				str.release();
				assert(str.capacity < cap);
				assert(str.capacity == BasicString!char.MinimalCapacity);
				--------------------
		*/
		public void release()scope{
			this.core.release();
		}

		deprecated("use `.release()` instead")
		public void destroy()scope{
			this.release();
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

				const size_t cap = (str.capacity * 2);
				str.reserve(cap);
				assert(str.capacity > BasicString!char.MinimalCapacity);
				assert(str.capacity >= cap);
				--------------------
		*/
		public size_t reserve(const size_t n)scope{
			return this.core.reserve(n);
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
		public void resize(const size_t n, const Char ch = '_')scope{
			const size_t old_length = this.length;

			if(old_length > n){
				()@trusted{
					this.core.length = n;
				}();
			}
			else if(old_length < n){
				this.append(ch, n - old_length);
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
		public size_t shrinkToFit()scope{
			return this.core.shrinkToFit();
		}



		/**
			Destroys the `BasicString` object.

			This deallocates all the storage capacity allocated by the `BasicString` using its allocator.
		*/
		public ~this()scope{
		}



		/**
			Constructs a empty `BasicString` object.

			Examples:
				--------------------
				{
					BasicString!char str = null;
					assert(str.empty);
				}
				--------------------
		*/
		public this(typeof(null) nil)scope pure nothrow @safe @nogc{
		}



		/**
			Constructs a empty `BasicString` object with `allocator`.

			Parameters:
				`allocator` allocator parameter.

			Examples:
				--------------------
				{
					BasicString!(char, Mallocator) str = Mallocator.init;
					assert(str.empty);
				}
				--------------------
		*/
		public this(Allocator allocator)scope {
			this.core = Core(forward!allocator);
		}



		/**
			Constructs a `BasicString` object, initializing its value to char value `character`.

			Parameters:
				`character` can by type char|wchar|dchar.

			Examples:
				--------------------
				{
					BasicString!char str = 'x';
					assert(str == "x");
				}

				{
					BasicString!char str = '読';
					assert(str == "読");
				}
				--------------------
		*/
		public this(C)(const C character)scope
		if(isSomeChar!C){
			this.core.ctor(character);
		}



		/**
			Constructs a `BasicString` object, initializing its value to char value `character`.

			Parameters:
				`character` can by type char|wchar|dchar.

				`allocator` allocator parameter.

			Examples:
				--------------------
				{
					auto str = BasicString!(char, Mallocator)('読', Mallocator.init);
					assert(str == "読");
				}
				--------------------
		*/
		public this(C)(const C character, Allocator allocator)scope
		if(isSomeChar!C){
			this.core = Core(forward!allocator);
			this.core.ctor(character);
		}



		/**
			Constructs a `BasicString` object from char slice `slice`.

			Parameters:
				`slice` is slice of characters (`const char[]`, `const wchar[]`, `const dchar[]`).

			Examples:
				--------------------
				{
					BasicString!char str = "test";
					assert(str == "test");
				}

				{
					BasicString!char str = "test 読"d;
					assert(str == "test 読");
				}

				{
					wchar[] data = [cast(wchar)'1', '2', '3'];
					BasicString!char str = data;
					assert(str == "123");
				}
				--------------------
		*/
		public this(this This)(scope const Char[] slice)scope{
			this.core.ctor(slice);
		}

		/// ditto
		public this(this This, C)(scope const C[] slice)scope
		if(isSomeChar!C && !is(immutable C == immutable Char)){
			this.core.ctor(slice);
		}



		/**
			Constructs a `BasicString` object from char slice `slice`.

			Parameters:
				`slice` is slice of characters (`const char[]`, `const wchar[]`, `const dchar[]`).

				`allocator` allocator parameter.

			Examples:
				--------------------
				{
					auto str = BasicString!(char, Mallocator)("test", Mallocator.init);
					assert(str == "test");
				}

				{
					auto str = BasicString!(char, Mallocator)("test 読"d, Mallocator.init);
					assert(str == "test 読");
				}

				{
					wchar[] data = [cast(wchar)'1', '2', '3'];
					auto str = BasicString!(char, Mallocator)(data, Mallocator.init);
					assert(str == "123");
				}
				--------------------
		*/
		public this(this This)(scope const Char[] slice, Allocator allocator)scope{
			this.core = Core(forward!allocator);
			this.core.ctor(slice);
		}

		/// ditto
		public this(this This, C)(scope const C[] slice, Allocator allocator)scope
		if(isSomeChar!C && !is(immutable C == immutable Char)){
			this.core = Core(forward!allocator);
			this.core.ctor(slice);
		}



		/**
			Constructs a `BasicString` object, initializing its value from integer `integer`.

			Parameters:

				`integer` integers value.

			Examples:
				--------------------
				{
					BasicString!char str = 123uL;
					assert(str == "123");
				}

				{
					BasicString!dchar str = -123;
					assert(str == "-123");
				}
				--------------------
		*/
		public this(I)(I integer)scope
		if(isIntegral!I){
			this.core.ctor(integer);
		}



		/**
			Constructs a `BasicString` object, initializing its value from integer `integer`.

			Parameters:

				`integer` integers value.

				`allocator` allocator parameter.

			Examples:
				--------------------
				{
					auto str = BasicString!(char, Mallocator)(123uL, Mallocator.init);
					assert(str == "123");
				}

				{
					auto str = BasicString!(dchar, Mallocator)(-123, Mallocator.init);
					assert(str == "-123");
				}
				--------------------
		*/
		public this(I)(I integer, Allocator allocator)scope
		if(isIntegral!I){
			this.core = Core(forward!allocator);
			this.core.ctor(integer);
		}



		/**
			Constructs a `BasicString` object from other `BasicString` object.

			Parameters:

				`rhs` `BasicString` rvalue/lvalue

				`allocator` optional allocator parameter.

			Examples:
				--------------------
				{
					BasicString!char a = "123";
					BasicString!char b = a;
					assert(b == "123");
				}

				{
					BasicString!dchar a = "123";
					BasicString!char b = a;
					assert(b == "123");
				}

				{
					BasicString!dchar a = "123";
					auto b = BasicString!char(a, Mallocator.init);
					assert(b == "123");
				}

				import core.lifetime : move;
				{
					BasicString!char a = "123";
					BasicString!char b = move(a);
					assert(b == "123");
				}
				--------------------
		*/
		public this(this This, Rhs)(auto ref scope const Rhs rhs)scope
		if(    isBasicString!Rhs
			&& isConstructable!(rhs, This)
			&& (isRef!rhs || !is(immutable This == immutable Rhs))
		){
			this(forward!rhs, Evoid.init);
		}

		/// ditto
		public this(this This, Rhs)(auto ref scope const Rhs rhs, Allocator allocator)scope
		if(isBasicString!Rhs){
			this.core = Core(forward!allocator);
			this.core.ctor(rhs.core.chars);
			//this(rhs.core.chars, forward!allocator);
		}

		/// ditto
		public this(this This, Rhs)(auto ref scope const Rhs rhs, Evoid)scope
		if(isBasicString!Rhs && isConstructable!(rhs, This)){
			static if(false && isMoveConstructable!(rhs, This)){    //TODO
				/+
				static if(!hasStatelessAllocator)
					this.core = Core(move(rhs.core.allcoator));

				this.core.ctor(rhs.core.chars);


				static if(!hasStatelessAllocator)
					this._allcoator = move(rhs._allcoator);

				()@trusted{
					if(rhs._sso){
						this._short = rhs._short;
					}
					else{
						this._long = rhs._long;
						rhs._short = Short.init;
					}
				}();+/
			}
			else static if(isCopyConstructable!(rhs, This)){
				static if(!hasStatelessAllocator)
					this.core = Core(rhs.core.allcoator);

				this.core.ctor(rhs.core.chars);
			}
			else static assert(0, "no impl");
		}




		/**
			Copy constructor if `Allocator` is statless.

			Parameter `rhs` is const.
		*/
		static if(hasStatelessAllocator)
		public this(ref scope const typeof(this) rhs)scope{
			this(rhs.core.chars);
		}



		/**
			Copy constructor if `Allocator` has state.

			Parameter `rhs` is mutable.
		*/
		static if(!hasStatelessAllocator)
		public this(ref scope typeof(this) rhs)scope{
			this(rhs.core.chars, rhs.allocator);
		}



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
		public ref typeof(this) opAssign(typeof(null) nil)scope pure nothrow @safe @nogc{
			this.clear();
			return this;
		}

		/// ditto
		public ref typeof(this) opAssign(scope const Char[] slice)scope{
			this.clear();

			this.reserve(encodedLength!Char(slice));
			()@trusted{
				this.core.length = slice.encodeTo(this.core.allChars);
			}();

			return this;
		}

		/// ditto
		public ref typeof(this) opAssign(C)(scope const C[] slice)scope
		if(isSomeChar!C){
			this.clear();

			this.reserve(encodedLength!Char(slice));
			()@trusted{
				this.core.length = slice.encodeTo(this.core.allChars);
			}();

			return this;
		}

		/// ditto
		public ref typeof(this) opAssign(C)(const C character)scope
		if(isSomeChar!C){
			this.clear();

			assert(character.encodedLength!Char <= MinimalCapacity);
			()@trusted{
				this.core.length = character.encodeTo(this.core.allChars);
			}();

			return this;
		}

		/// ditto
		public ref typeof(this) opAssign(I)(const I integer)scope
		if(isIntegral!I){
			this.clear();

			assert(integer.encodedLength!Char <= MinimalCapacity);
			()@trusted{
				this.core.length = integer.encodeTo(this.core.allChars);
			}();

			return this;
		}

		/// ditto
		public ref typeof(this) opAssign(Rhs)(auto ref scope Rhs rhs)scope
		if(isBasicString!Rhs){
			return this.opAssign(rhs.core.chars);
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
		public template opOpAssign(string op)
		if(op == "+" || op == "~"){
			alias opOpAssign = append;
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
		public typeof(this) opBinary(string op)(scope const Char[] rhs)scope
		if(op == "+" || op == "~"){
			static if(hasStatelessAllocator)
				return this.build(this.core.chars, rhs);
			else
				return this.build(this.core.allocator, this.core.chars, rhs);
		}

		/// ditto
		public typeof(this) opBinary(string op, Rhs)(auto ref scope const Rhs rhs)scope
		if((op == "+" || op == "~")
			&& (isBasicString!Rhs || isSomeChar!Rhs || isSomeString!Rhs || isCharArray!Rhs || isIntegral!Rhs)
		){
			static if(hasStatelessAllocator)
				return this.build(this.core.chars, forward!rhs);
			else
				return this.build(this.core.allocator, this.core.chars, forward!rhs);
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
		public typeof(this) opBinaryRight(string op)(scope const Char[] lhs)scope
		if(op == "+" || op == "~"){
			static if(hasStatelessAllocator)
				return this.build(lhs, this.core.chars);
			else
				return this.build(this.core.allocator, lhs, this.core.chars);
		}

		/// ditto
		public typeof(this) opBinaryRight(string op, Lhs)(auto ref scope const Lhs lhs)scope
		if((op == "+" || op == "~")
			&& (isSomeChar!Lhs || isSomeString!Lhs || isCharArray!Lhs || isIntegral!Lhs)
		){
			static if(hasStatelessAllocator)
				return this.build(forward!lhs, this.core.chars);
			else
				return this.build(this.core.allocator, forward!lhs, this.core.chars);
		}



		/**
			Calculates the hash value of string.
		*/
		public size_t toHash()const pure nothrow @safe @nogc{
			return hashOf(this.core.chars);
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
		public bool opEquals(scope const Char[] rhs)const scope pure nothrow @safe @nogc{
			return this._op_equals(rhs[]);
		}

		/// ditto
		public bool opEquals(Rhs)(auto ref scope Rhs rhs)const scope
		if(isBasicString!Rhs || isSomeChar!Rhs || isSomeString!Rhs || isCharArray!Rhs || isIntegral!Rhs || isInputCharRange!Rhs){

			static if(isBasicString!Rhs){
				return this._op_equals(rhs.core.chars);
			}
			else static if(isSomeString!Rhs || isCharArray!Rhs){
				return this._op_equals(rhs[]);
			}
			else static if(isSomeChar!Rhs){
				import std.range : only;
				return this._op_equals(only(rhs));
			}
			else static if(isIntegral!Rhs){
				import std.conv : toChars;
				return  this._op_equals(toChars(rhs + 0));
			}
			else static if(isInputRange!Rhs){
				return this._op_equals(rhs);
			}
			else{
				static assert(0, "invalid type '" ~ Rhs.stringof ~ "'");
			}
		}


		private bool _op_equals(Range)(auto ref scope Range rhs)const scope
		if(isInputCharRange!Range){
			import std.range : empty, hasLength;

			alias RhsChar = Unqual!(ElementEncodingType!Range);
			auto lhs = this.core.chars;

			enum bool lengthComperable = hasLength!Range && is(Unqual!Char == RhsChar);

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
		public int opCmp(scope const Char[] rhs)const scope pure nothrow @safe @nogc{
			return this._op_cmp(rhs[]);
		}

		/// ditto
		public int opCmp(Rhs)(auto ref scope Rhs rhs)const scope
		if(isBasicString!Rhs || isSomeChar!Rhs || isSomeString!Rhs || isCharArray!Rhs || isIntegral!Rhs || isInputCharRange!Rhs){

			static if(isBasicString!Val){
				return this._op_cmp(rhs._chars);
			}
			else static if(isSomeString!Val || isCharArray!Val){
				return this._op_cmp(rhs[]);
			}
			else static if(isSomeChar!Val){
				import std.range : only;
				return this._op_cmp(only(rhs));
			}
			else static if(isIntegral!Val){
				import std.conv : toChars;
				return this._op_cmp(toChars(rhs + 0));
			}
			else static if(isInputRange!Val){
				return this._op_cmp(val);
			}
			else{
				static assert(0, "invalid type '" ~ Val.stringof ~ "'");
			}
		}


		private int _op_cmp(Range)(Range rhs)const scope
		if(isInputCharRange!Range){
			import std.range : empty;

			auto lhs = this.core.chars;
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
		public inout(Char)[] opIndex()inout return pure nothrow @system @nogc{
			return this.core.chars;
		}



		/**
			Returns character at specified location `pos`.

			Examples:
				--------------------
				BasicString!char str = "abcd";

				assert(str[1] == 'b');
				--------------------
		*/
		public Char opIndex(const size_t pos)const scope pure nothrow @trusted @nogc{
			assert(0 <= pos && pos < this.length);

			return *(this.ptr + pos);
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
		public inout(Char)[] opSlice(const size_t begin, const size_t end)inout return pure nothrow @system @nogc{
			const len = this.length;
			return this.ptr[min(len, begin) .. min(len, end)];
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
		public Char opIndexAssign(const Char val, const size_t pos)scope pure nothrow @trusted @nogc{
			assert(0 <= pos && pos < this.length);

			return *(this.ptr + pos) = val;
		}



		/**
			Returns the length of the string, in terms of number of characters.

			Same as `length()`.
		*/
		public size_t opDollar()const scope pure nothrow @safe @nogc{
			return this.length;
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
		public void proxySwap(ref scope typeof(this) rhs)scope pure nothrow @trusted @nogc{
			this.core.proxySwap(rhs.core);

		}



		/**
			Extends the `BasicString` by appending additional characters at the end of string.

			Return number of inserted characters.

			Parameters:
				`val` appended value.

				`count` Number of times `val` is appended.

			Examples:
				--------------------
                {
				    BasicString!char str = "123456";

				    str.append('x', 2);
				    assert(str == "123456xx");
                }

                {
				    BasicString!char str = "123456";

				    str.append("abc");
				    assert(str == "123456abc");
                }

                {
				    BasicString!char str = "123456";
				    BasicString!char str2 = "xyz";

				    str.append(str2);
				    assert(str == "123456xyz");
                }

                {
				    BasicString!char str = "12";

				    str.append(+34);
				    assert(str == "1234");
                }
				--------------------
		*/
		public size_t append(const Char[] val, const size_t count = 1)scope{
			return this.core.append(val, count);
		}

		/// ditto
		public size_t append(Val)(auto ref scope const Val val, const size_t count = 1)scope
		if(isBasicString!Val || isSomeChar!Val || isSomeString!Val || isCharArray!Val || isIntegral!Val){

			static if(isBasicString!Val){
				return this.core.append(val.core.chars, count);
			}
			else static if(isSomeString!Val || isCharArray!Val){
				return this.core.append(val[], count);
			}
			else static if(isSomeChar!Val || isIntegral!Val){
				return this.core.append(val, count);
			}
			else{
				static assert(0, "invalid type '" ~ Val.stringof ~ "'");
			}
		}



		/**
			Inserts additional characters into the `BasicString` right before the character indicated by `pos` or `ptr`.

			Return number of inserted characters.

			If parameters are out of range then there is no inserted value and in debug mode assert throw error.

			Parameters are out of range if `pos` is larger then `.length` or `ptr` is smaller then `this.ptr` or `ptr` point to address larger then `this.ptr + this.length`

			Parameters:
				`pos` Insertion point, the new contents are inserted before the character at position `pos`.

				`ptr` Pointer pointing to the insertion point, the new contents are inserted before the character pointed by ptr.

				`val` Value inserted before insertion point `pos` or `ptr`.

				`count` Number of times `val` is inserted.

			Examples:
				--------------------
                {
				    BasicString!char str = "123456";

				    str.insert(2, 'x', 2);
				    assert(str == "12xx3456");
                }

                {
				    BasicString!char str = "123456";

				    str.insert(2, "abc");
				    assert(str == "12abc3456");
                }

                {
				    BasicString!char str = "123456";
				    BasicString!char str2 = "abc";

				    str.insert(2, str2);
				    assert(str == "12abc3456");
                }

                {
				    BasicString!char str = "123456";

				    str.insert(str.ptr + 2, 'x', 2);
				    assert(str == "12xx3456");
                }

                {
				    BasicString!char str = "123456";

				    str.insert(str.ptr + 2, "abc");
				    assert(str == "12abc3456");
                }

                {
				    BasicString!char str = "123456";
				    BasicString!char str2 = "abc";

				    str.insert(str.ptr + 2, str2);
				    assert(str == "12abc3456");
                }
				--------------------

		*/
		public size_t insert(const size_t pos, const scope Char[] val, const size_t count = 1)scope{
			return this.core.insert(pos, val, count);
		}

		/// ditto
		public size_t insert(Val)(const size_t pos, auto ref const scope Val val, const size_t count = 1)scope
		if(isBasicString!Val || isSomeChar!Val || isSomeString!Val || isIntegral!Val){
			static if(isBasicString!Val || isSomeString!Val)
				return this.core.insert(pos, val[], count);
			else static if(isSomeChar!Val || isIntegral!Val)
				return this.core.insert(pos, val, count);
			else static assert(0, "invalid type '" ~ Val.stringof ~ "'");
		}

		/// ditto
		public size_t insert(const Char* ptr, const scope Char[] val, const size_t count = 1)scope{
			const size_t pos = this._insert_ptr_to_pos(ptr);

			return this.core.insert(pos, val, count);
		}

		/// ditto
		public size_t insert(Val)(const Char* ptr, auto ref const scope Val val, const size_t count = 1)scope
		if(isBasicString!Val || isSomeChar!Val || isSomeString!Val || isIntegral!Val){
			const size_t pos = this._insert_ptr_to_pos(ptr);

			static if(isBasicString!Val || isSomeString!Val)
				return this.core.insert(pos, val[], count);
			else static if(isSomeChar!Val || isIntegral!Val)
				return this.core.insert(pos, val, count);
			else
				static assert(0, "invalid type '" ~ Val.stringof ~ "'");
		}


		private size_t _insert_ptr_to_pos(const Char* ptr)scope const pure nothrow @trusted @nogc{
			const chars = this.core.chars;

			return (ptr > chars.ptr)
				? (ptr - chars.ptr)
				: 0;
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
                {
				    BasicString!char str = "123456";

				    str.erase(2);
				    assert(str == "12");
                }

                {
				    BasicString!char str = "123456";

				    str.erase(1, 2);
				    assert(str == "23");
                }

                {
				    BasicString!char str = "123456";

				    str.erase(str.ptr + 2);
				    assert(str == "12456");
                }

                {
				    BasicString!char str = "123456";

				    str.erase(str[1 .. $-1]);
				    assert(str == "2345");
                }
				--------------------
		*/
		public void erase(const size_t pos)scope pure nothrow @trusted @nogc{
			this.core.length = min(this.length, pos);
		}

		/// ditto
		public void erase(const size_t pos, const size_t n)scope pure nothrow @trusted @nogc{
			const chars = this.core.chars;

			if(pos >= this.length)
				return;

			this.core.erase(pos, n);
		}

		/// ditto
		public void erase(scope const Char* ptr)scope pure nothrow @trusted @nogc{
			const chars = this.core.chars;

			if(ptr <= chars.ptr)
				this.core.length = 0;
			else
				this.core.length = min(chars.length, ptr - chars.ptr);
		}

		/// ditto
		public void erase(scope const Char[] slice)scope pure nothrow @trusted @nogc{
			const chars = this.core.chars;

			if(slice.ptr <= chars.ptr){
				const size_t offset = (chars.ptr - slice.ptr);

				if(slice.length <= offset)
					return;

				enum size_t pos = 0;
				const size_t len = (slice.length - offset);

				this.core.erase(pos, len);
			}
			else{
				const size_t offset = (slice.ptr - chars.ptr);

				if(chars.length <= offset)
					return;

				alias pos = offset;
				const size_t len = slice.length;

				this.core.erase(pos, len);

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
                {
				    BasicString!char str = "123456";

				    str.replace(2, 2, 'x', 5);
				    assert(str == "12xxxxx56");
                }

                {
				    BasicString!char str = "123456";

				    str.replace(2, 2, "abcdef");
				    assert(str == "12abcdef56");
                }

                {
				    BasicString!char str = "123456";
				    BasicString!char str2 = "xy";

				    str.replace(2, 3, str2);
				    writeln(str[]);
				    assert(str == "12xy56");
                }

                {
				    BasicString!char str = "123456";

				    str.replace(str[2 .. 4], 'x', 5);
				    assert(str == "12xxxxx56");
                }

                {
				    BasicString!char str = "123456";

				    str.replace(str[2 .. 4], "abcdef");
				    assert(str == "12abcdef56");
                }

                {
				    BasicString!char str = "123456";
				    BasicString!char str2 = "xy";

				    str.replace(str[2 .. $], str2);
				    assert(str == "12xy56");
                }
				--------------------
		*/
		public ref typeof(this) replace(const size_t pos, const size_t len, scope const Char[] val, const size_t count = 1)return scope{
			this.core.replace(pos, len, val, count);
			return this;
		}

		/// ditto
		public ref typeof(this) replace(Val)(const size_t pos, const size_t len, auto ref scope const Val val, const size_t count = 1)return scope
		if(isBasicString!Val || isSomeChar!Val || isSomeString!Val || isIntegral!Val || isCharArray!Val){

			static if(isBasicString!Val || isSomeString!Val || isCharArray!Val)
				this.core.replace(pos, len, val[], count);
			else static if(isSomeChar!Val || isIntegral!Val)
				this.core.replace(pos, len, val, count);
			else
				static assert(0, "invalid type '" ~ Val.stringof ~ "'");

			return this;
		}

		/// ditto
		public ref typeof(this) replace(scope const Char[] slice, scope const Char[] val, const size_t count = 1)return scope{
			this.core.replace(slice, val, count);
			return this;
		}

		/// ditto
		public ref typeof(this) replace(Val)(scope const Char[] slice, auto ref scope const Val val, const size_t count = 1)return scope
		if(isBasicString!Val || isSomeChar!Val || isSomeString!Val || isIntegral!Val || isCharArray!Val){

			static if(isBasicString!Val || isSomeString!Val || isCharArray!Val)
				this.core.replace(slice, val[], count);
			else static if(isSomeChar!Val || isIntegral!Val)
				this.core.replace(slice, val, count);
			else
				static assert(0, "invalid type '" ~ Val.stringof ~ "'");

			return this;
		}



		///Alias to append.
		public alias put = append;

		///Alias to `popBackCodeUnit`.
		public alias popBack = popBackCodeUnit;

		///Alias to `frontCodeUnit`.
		public alias front = frontCodeUnit;

		///Alias to `backCodeUnit`.
		public alias back = backCodeUnit;


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
		public static typeof(this) build(Args...)(auto ref scope const Args args)
		if(Args.length > 0 && !is(immutable Args[0] == immutable Allocator)){
			import core.lifetime : forward;

			auto result = BasicString.init;

			result._build_impl(forward!args);

			return ()@trusted{
				return result;
			}();
		}

		/// dito
		public static typeof(this) build(Args...)(Allocator allocator, auto ref scope const Args args){
			import core.lifetime : forward;

			auto result = BasicString(forward!allocator);

			result._build_impl(forward!args);

			return ()@trusted{
				return result;
			}();
		}

		private void _build_impl(Args...)(auto ref scope const Args args)scope{
			import std.traits : isArray;

			assert(this.empty);
			//this.clear();
			size_t new_length = 0;

			static foreach(enum I, alias Arg; Args){
				static if(isBasicString!Arg)
					new_length += encodedLength!Char(args[I].core.chars);
				else static if(isArray!Arg &&  isSomeChar!(ElementEncodingType!Arg))
					new_length += encodedLength!Char(args[I][]);
				else static if(isSomeChar!Arg)
					new_length += encodedLength!Char(args[I]);
				else static assert(0, "wrong type '" ~ typeof(args[I]).stringof ~ "'");
			}

			if(new_length == 0)
				return;


			alias result = this;

			result.reserve(new_length);



			Char[] data = result.core.allChars;

			static foreach(enum I, alias Arg; Args){
				static if(isBasicString!Arg)
					data = data[args[I].core.chars.encodeTo(data) .. $];
				else static if(isArray!Arg)
					data = data[args[I][].encodeTo(data) .. $];
				else static if(isSomeChar!Arg)
					data = data[args[I].encodeTo(data) .. $];
				else static assert(0, "wrong type '" ~ Arg.stringof ~ "'");
			}

			()@trusted{
				result.core.length = new_length;
			}();
		}
	}
}



/// ditto
template BasicString(
	_Char,
	size_t _Padding,
	_Allocator = Mallocator
)
if(isSomeChar!_Char && is(Unqual!_Char == _Char)){
	alias BasicString = .BasicString!(_Char, _Allocator, _Padding);
}

private{
	auto frontCodeUnit(Range)(auto ref Range r){
		import std.traits : isAutodecodableString;

		static if(isAutodecodableString!Range){
			assert(r.length > 0);
			return r[0];
		}
		else{
			import std.range.primitives : front;
			return  r.front;
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
			return  r.popFront;
		}
	}
}
version(unittest){
	//ctor(null) and ctor(allcoator)
	pure nothrow @safe @nogc unittest{
		{
			BasicString!char str = null;
			assert(str.empty);
		}

		{
			BasicString!(char, Mallocator) str = Mallocator.init;
			assert(str.empty);
		}
	}

	//ctor(char) and ctor(char, allcoator)
	pure nothrow @safe @nogc unittest{
		{
			BasicString!char str = 'x';
			assert(str == "x");
		}

		{
			BasicString!char str = '読';
			assert(str == "読");
		}

		{
			auto str = BasicString!(char, Mallocator)('x', Mallocator.init);
			assert(str == "x");
		}
	}

	//ctor(slice) and ctor(slice, allocator)
	pure nothrow @safe unittest{
		{
			BasicString!char str = "test";
			assert(str == "test");
		}

		{
			BasicString!char str = "test 読"d;
			assert(str == "test 読");
		}

		{
			wchar[] data = [cast(wchar)'1', '2', '3'];
			BasicString!char str = data;
			assert(str == "123");
		}
	}

	//ctor(slice) and ctor(slice, allocator)
	pure nothrow @safe @nogc unittest{
		{
			BasicString!char str = 123;
			assert(str == "123");
		}

		{
			BasicString!dchar str = 321;
			assert(str == "321");
			assert(str == "321"d);
		}

		{
			auto str = BasicString!(wchar, Mallocator)(42, Mallocator.init);
			assert(str == "42");
		}
	}

	//ctor(integer) and ctor(integer, allocator)
	pure nothrow @safe @nogc unittest{
		{
			BasicString!char str = 123uL;
			assert(str == "123");
		}

		{
			BasicString!dchar str = -123;
			assert(str == "-123");
		}

		{
			auto str = BasicString!(char, Mallocator)(123uL, Mallocator.init);
			assert(str == "123");
		}

		{
			auto str = BasicString!(dchar, Mallocator)(-123, Mallocator.init);
			assert(str == "-123");
		}
	}

	//ctor(BasicString) and ctor(BasicString, allocator)
	pure nothrow @safe @nogc unittest{
		{
			BasicString!char a = "123";
			BasicString!char b = a;
			assert(b == "123");
		}

		{
			BasicString!dchar a = "123";
			BasicString!char b = a;
			assert(b == "123");
		}

		{
			BasicString!dchar a = "123";
			auto b = BasicString!char(a, Mallocator.init);
			assert(b == "123");
		}

		import core.lifetime : move;
		{
			BasicString!char a = "123";
			BasicString!char b = move(a);
			assert(b == "123");
		}
	}

}


//const char test:
pure nothrow @safe @nogc unittest{

}
