module basic_string.core;

import std.traits : Unqual, Unconst, isSomeChar, isSomeString, isIntegral;

import basic_string.internal.mallocator;
import basic_string.internal.encoding;
import basic_string.internal.traits;


package struct Evoid{}


package template isBasicStringCore(T...)
if(T.length == 1){
    enum bool isBasicStringCore = is(Unqual!(T[0]) == BasicStringCore!Args, Args...);
}

package template BasicStringCore(
    _Char,
    _Allocator,
    size_t _Padding
){
    import core.lifetime : forward, move;
    import std.experimental.allocator.common :  stateSize;
    import std.traits : hasMember, isSafe;


    version(BigEndian){
        static assert(0, "big endian systems are not supported");
    }
    else version(LittleEndian){

        struct Long{
            size_t capacity;
            size_t length;
            _Char* ptr;
            _Char[_Padding] padding;

            @property isLong()scope const pure nothrow @safe @nogc{
                return (this.capacity & cast(size_t)0x1) == 0;
            }

            enum size_t maxCapacity = ((size_t.max / _Char.sizeof) & ~cast(size_t)0x1);
        }

        static if((Long.sizeof / _Char.sizeof) <= ubyte.max)
            alias ShortLength = ubyte;
        else static if((Long.sizeof / _Char.sizeof) <= ushort.max)
            alias ShortLength = ushort;
        else static if((Long.sizeof / _Char.sizeof) <= uint.max)
            alias ShortLength = uint;
        else static if((Long.sizeof / _Char.sizeof) <= ulong.max)
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
                return (this.flag & 0x1) == 1;
            }

            void setShort()scope pure nothrow @safe @nogc{
                this.flag = 0x1;
            }
        }

        static assert(Long.sizeof == Short.sizeof);
    }
    else static assert(0, "no impl");

    struct BasicStringCore{
        public enum bool hasStatelessAllocator = (stateSize!_Allocator == 0);

        public alias Char = _Char;

        public alias Allocator = _Allocator;

        static if(hasStatelessAllocator){
            public alias allocator = Allocator.instance;

            private enum safeAllocate = isSafe!((){
                size_t capacity = size_t.max;

                cast(void)allocator.allocate(capacity);
            });
        }
        else{
            public Allocator allocator;

            private enum safeAllocate = isSafe!((ref Allocator a){
                size_t capacity = size_t.max;

                cast(void)a.allocate(capacity);
            });
        }

        //private alias _allocator = allocator;


        public alias MaximalCapacity = Long.maxCapacity;

        public alias MinimalCapacity = Short.capacity;


        public ~this()scope{
            if(!this._sso){
                this._deallocate(this._long_all_chars());
                debug this._short.setShort();
                debug this._short.length = 0;
            }
        }

        public this(this This)(Allocator allocator){
            static if(!hasStatelessAllocator)
                this._allocator = forward!allocator;
        }

        public this(this This, Rhs)(auto ref scope const Rhs rhs, Evoid )scope
        if(isBasicStringCore!Rhs){

        }


        public void ctor(C)(const C character)scope
        if(isSomeChar!C){
            assert(this._sso);
            this._short.length = cast(ShortLength)character.encodeTo(this._short_all_chars);    //this._short.data[0] = c;;
        }

        public void ctor(this This, C)(scope const C[] str)scope
        if(isSomeChar!C){
            auto self = (()@trusted => cast(Unqual!This*)&this )();
            assert(self._sso);

            const size_t str_length = encodedLength!Char(str);

            if(str_length > self._short.capacity){


                const size_t new_capacity = ((str_length + 1) & ~0x1);

                assert(new_capacity >= str_length);
                assert(new_capacity % 2 == 0);


                Char[] cdata = self._allocate(new_capacity);

                ()@trusted{
                    self._long.ptr = cdata.ptr;
                    self._long.length = str[].encodeTo(cdata[]);   //cdata[] = str[];
                    self._long.capacity = new_capacity;
                }();
                assert(!self._sso);

            }
            else if(str.length != 0){
                assert(this._sso);

                self._short.length = cast(ShortLength)str[].encodeTo(self._short_all_chars);   //this._short.data[0 .. str_length] = str[];   ///str_length;
                assert(this.capacity == Short.capacity);
            }
            else{
                assert(this._sso);
                assert(this.capacity == Short.capacity);
                assert(this._short.length == 0);
            }
        }

        public void ctor(I)(const I integer)scope
        if(isIntegral!I){
            const size_t len = encodedLength!Char(integer);

            this.reserve(len);
            const new_len = integer.encodeTo(this.allChars);
            ()@trusted{
                this.length = new_len;
            }();
        }


        public @property size_t length()const scope pure nothrow @trusted @nogc{
            return this._sso
                ? this._short_length
                : this._long_length;
        }


        public @property void length(const size_t len)scope pure nothrow @system @nogc{
            assert(len <= this.capacity);

            if(this._sso)
                this._short.length = cast(ShortLength)len;
            else
                this._long.length = len;
        }


        public @property size_t capacity()const scope pure nothrow @trusted @nogc{
            return this._sso
                ? this._short_capacity
                : this._long_capacity;
        }


        public @property bool small()const scope pure nothrow @safe @nogc{
            return this._sso;
        }


        public @property inout(Char)* ptr()inout return pure nothrow @system @nogc{
            return this._sso
                ? this._short_ptr
                : this._long_ptr;
        }


        public @property inout(Char)[] chars()inout scope pure nothrow @trusted @nogc{
            return this._sso
                ? this._short_chars()
                : this._long_chars();
        }


        public @property inout(Char)[] allChars()inout scope pure nothrow @trusted @nogc{
            return this._sso
                ? this._short_all_chars()
                : this._long_all_chars();
        }


        public void release()scope{
            if(this._sso){
                this._short.length = 0;
            }
            else{
                this._deallocate(this._long_all_chars);

                this._short.setShort();
                this._short.length = 0;
            }
        }


        public size_t reserve(const size_t n)scope{
            size_t _reserve_short(const size_t n)scope{
                assert(this._sso);

                enum size_t old_capacity = this._short.capacity;

                if(n <= old_capacity)
                    return old_capacity;

                const size_t length = this._short_length;
                const size_t new_capacity = max(old_capacity * 2, (n + 1)) & ~0x1;

                //assert(new_capacity >= max(old_capacity * 2, n));
                assert(new_capacity % 2 == 0);


                Char[] cdata = this._allocate(new_capacity);

                ()@trusted{
                    memCopy(cdata.ptr, this._short_ptr, length);    //cdata[0 .. length] = this._short_chars();
                    assert(this.chars == cdata[0 .. length]); //assert(this._chars == cdata[0 .. length]);

                    this._long.capacity = new_capacity;
                    assert(!this._sso);
                    this._long.ptr = cdata.ptr;
                    this._long.length = length;
                }();

                return new_capacity;
            }

            size_t _reserve_long(const size_t n)scope{
                assert(!this._sso);

                const size_t old_capacity = this._long_capacity;

                if(n <= old_capacity)
                    return old_capacity;

                const size_t length = this._long_length;
                const size_t new_capacity = max(old_capacity * 2, (n + 1)) & ~0x1;

                //assert(new_capacity >= max(old_capacity * 2, n));
                assert(new_capacity % 2 == 0);

                Char[] cdata = this._reallocate(this._long_all_chars(), length, new_capacity);

                ()@trusted{
                    this._long.capacity = new_capacity;
                    this._long.ptr = cdata.ptr;
                    assert(!this._sso);
                }();

                return new_capacity;

            }

            return (this._sso)
                ? _reserve_short(n)
                : _reserve_long(n);
        }


        public size_t shrinkToFit()scope{
            if(this._sso)
                return MinimalCapacity;

            const size_t old_capacity = this._long_capacity;
            const size_t length = this._long_length;


            if(length == old_capacity)
                return length;

            Char[] cdata = this._long_all_chars();

            if(length <= MinimalCapacity){
                //alias new_capacity = length;

                this._short.setShort();
                this._short.length = cast(ShortLength)length;

                ()@trusted{
                    memCopy(this._short_ptr, cdata.ptr, length);    //this._short.data[0 .. length] = cdata[0 .. length];
                }();

                this._deallocate(cdata);

                assert(this._sso);
                return MinimalCapacity;
            }

            const size_t new_capacity = (length + 1) & ~0x1;

            if(new_capacity >= old_capacity)
                return old_capacity;

            assert(new_capacity >= length);
            assert(new_capacity % 2 == 0);

            cdata = this._reallocate_optional(cdata, new_capacity);

            ()@trusted{
                this._long.ptr = cdata.ptr;
                this._long.capacity = new_capacity;
                assert(!this._sso);
            }();

            return new_capacity;
        }


        public void proxySwap(ref scope typeof(this) rhs)scope pure nothrow @trusted @nogc{
            import std.algorithm.mutation : swap;
            swap(this._raw, rhs._raw);

            static if(!hasStatelessAllocator)
                swap(this._allocator, rhs._allocator);

        }


        public size_t append(Val)(const Val val, const size_t count)scope
        if(isSomeChar!Val || isSomeString!Val || isIntegral!Val){
            if(count == 0)
                return 0;

            const size_t old_length = this.length;
            const size_t new_count = count * encodedLength!Char(val);

            Char[] new_chars = this._expand(new_count);
            const size_t tmp = val.encodeTo(new_chars, count);
            assert(tmp == new_count);

            return tmp;
        }


        public size_t insert(Val)(const size_t pos, const Val val, const size_t count)scope
        if(isSomeChar!Val || isSomeString!Val || isIntegral!I){

            const size_t new_count = count * encodedLength!Char(val);
            if(new_count == 0)
                return 0;

            Char[] new_chars = this._expand_move(pos, new_count);

            return val.encodeTo(new_chars, count);
        }


        public void erase(const size_t pos, const size_t n)scope pure nothrow @trusted @nogc{
            const len = this.length;
            assert(pos < len);

            const size_t top = (pos + n);

            if(top >= len)
                this.length = pos;
            else if(n != 0)
                this._reduce_move(top, n);
        }





        public void replace(Val)(scope const Char[] slice, scope const Val val, const size_t count)return scope
        if(isSomeChar!Val || isSomeString!Val || isIntegral!Val){
            const chars = this.chars;

            if(slice.ptr < chars.ptr){
                const size_t offset = (()@trusted => chars.ptr - slice.ptr)();
                const size_t pos = 0;
                const size_t len = (slice.length > offset)
                    ? (slice.length - offset)
                    : 0;

                this.replace(pos, len, val, count);
            }
            else{
                const size_t offset = (()@trusted => slice.ptr - chars.ptr)();
                const size_t pos = offset;
                const size_t len = slice.length;

                this.replace(pos, len, val, count);
            }
        }

        public void replace(Val)(const size_t pos, const size_t len, scope const Val val, const size_t count)return scope
        if(isSomeChar!Val || isSomeString!Val || isIntegral!Val){

            const size_t new_count = count * encodedLength!Char(val);
            if(new_count == 0){
                if(pos < this.length)
                    this.erase(pos, len);

                return;
            }

            assert(new_count != 0);

            auto chars = this.chars;
            const size_t old_length = chars.length;
            const size_t begin = min(pos, chars.length);    //alias begin = pos;

            const size_t end = min(chars.length, (pos + len));
            const size_t new_len = min(end - begin, new_count);
            //const size_t new_len = min(len, new_count);
            //const size_t end = (begin + new_len);


            if(begin == end){
                ///insert:
                Char[] new_chars = this._expand_move(begin, new_count);
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
                    this._reduce_move(end, (new_len - new_count));
                }();
            }
            else{
                ///asing + expand(insert):
                assert(new_count > new_len);

                const size_t expand_len = (new_count - new_len);

                Char[] new_chars = this._expand_move(end, expand_len);

                const x = val.encodeTo((()@trusted => (new_chars.ptr - new_len)[0 .. new_count])(), count);
                assert(x == new_count);
            }
        }

        private union{
            Short _short;
            Long _long;
            size_t[Long.sizeof / size_t.sizeof] _raw;

            static assert(typeof(_raw).sizeof == Long.sizeof);

            ref inout(Short) _get_short()inout return pure nothrow @trusted @nogc{
                return _short;
            }
        }


        //_long:
        private @property inout(Char)* _long_ptr()inout scope pure nothrow @nogc @trusted{
            assert(this._long.isLong);

            return this._long.ptr;
        }

        private @property inout(void)[] _long_data()inout scope pure nothrow @nogc @trusted{
            assert(this._long.isLong);

            return (cast(void*)this._long.ptr)[0 .. this._long.capacity * Char.sizeof];
        }

        private @property size_t _long_capacity()const scope pure nothrow @nogc @trusted{
            assert(this._long.isLong);

            return this._long.capacity;
        }

        private @property size_t _long_length()const scope pure nothrow @nogc @trusted{
            assert(this._long.isLong);

            return this._long.length;
        }

        private @property inout(Char)[] _long_chars()inout scope pure nothrow @nogc @trusted{
            assert(this._long.isLong);

            return this._long.ptr[0 .. this._long.length];
        }

        private @property inout(Char)[] _long_all_chars()inout scope pure nothrow @nogc @trusted{
            assert(this._long.isLong);

            return this._long.ptr[0 .. this._long.capacity];
        }


        //_short:
        private @property inout(Char)* _short_ptr()inout scope pure nothrow @nogc @trusted{
            assert(this._short.isShort);

            auto ret = this._short.data.ptr;
            return *&ret;
        }

        private @property inout(void)[] _short_data()inout scope pure nothrow @nogc @trusted{
            assert(this._short.isShort);

            auto ret = (cast(void*)this._short.data.ptr)[0 .. this._short.capacity * Char.sizeof];
            return *&ret;
        }

        private @property size_t _short_capacity()const scope pure nothrow @nogc @safe{
            assert(this._short.isShort);

            return this._short.capacity;
        }

        private @property auto _short_length()const scope pure nothrow @nogc @safe{
            assert(this._short.isShort);

            return this._short.length;
        }

        private @property inout(Char)[] _short_chars()inout scope pure nothrow @nogc @trusted{
            assert(this._short.isShort);

            auto ret = this._short.data[0 .. this._short.length];
            return *&ret;
        }

        private @property inout(Char)[] _short_all_chars()inout scope pure nothrow @nogc @trusted{
            assert(this._short.isShort);

            auto ret = this._short.data[];
            return *&ret;
        }


        //
        private @property bool _sso()const scope pure nothrow @trusted @nogc{
            assert(this._long.isLong != this._short.isShort);
            return this._short.isShort;
        }

        /+private @property inout(Char)[] _chars()inout scope pure nothrow @trusted @nogc{
            return this._sso
                ? this._short_chars()
                : this._long_chars();
        }

        private @property inout(Char)[] _all_chars()inout scope pure nothrow @trusted @nogc{
            return this._sso
                ? this._short_all_chars()
                : this._long_all_chars();
        }+/



        //allocation:
        private Char[] _allocate(const size_t capacity){
            void[] data = this.allocator.allocate(capacity * Char.sizeof);

            return (()@trusted => (cast(Char*)data.ptr)[0 .. capacity])();
        }

        private bool _deallocate(scope Char[] cdata){
            void[] data = ()@trusted{
                return (cast(void*)cdata.ptr)[0 .. cdata.length * Char.sizeof];

            }();

            static if(safeAllocate)
                return ()@trusted{
                    return this.allocator.deallocate(data);
                }();
            else
                return this.allocator.deallocate(data);
        }

        private Char[] _reallocate(scope return Char[] cdata, const size_t length, const size_t new_capacity){
            void[] data = (()@trusted => (cast(void*)cdata.ptr)[0 .. cdata.length * Char.sizeof] )();

            static if(hasMember!(typeof(allocator), "reallocate")){
                static if(safeAllocate)
                    const bool reallocated = ()@trusted{
                        return this.allocator.reallocate(data, new_capacity * Char.sizeof);
                    }();
                else
                    const bool reallocated = this.allocator.reallocate(data, new_capacity * Char.sizeof);
            }
            else
                enum bool reallocated = false;

            if(reallocated){
                assert(data.length / Char.sizeof == new_capacity);
                return (()@trusted => (cast(Char*)data.ptr)[0 .. new_capacity])();
            }

            Char[] new_cdata = this._allocate(new_capacity);
            ()@trusted{
                memCopy(new_cdata.ptr, cdata.ptr, length);  //new_cdata[0 .. length] = cdata[0 .. length];
            }();

            static if(safeAllocate)
                ()@trusted{
                    this.allocator.deallocate(data);
                }();
            else
                this.allocator.deallocate(data);

            return new_cdata;
        }

        private Char[] _reallocate_optional(scope return Char[] cdata, const size_t new_capacity)@trusted{
            void[] data = (cast(void*)cdata.ptr)[0 .. cdata.length * Char.sizeof];

            static if(hasMember!(typeof(allocator), "reallocate")){
                static if(safeAllocate)
                    const bool reallocated = ()@trusted{
                        return this.allocator.reallocate(data, new_capacity * Char.sizeof);
                    }();

                else
                    const bool reallocated = this.allocator.reallocate(data, new_capacity * Char.sizeof);

                if(reallocated){
                    assert(data.length / Char.sizeof == new_capacity);
                    return (cast(Char*)data.ptr)[0 .. new_capacity];
                }
            }

            return cdata;
        }



        //reduce/expand:
        private void _reduce_move(const size_t pos, const size_t n)scope pure nothrow @system @nogc{
            assert(pos  <= this.length);
            assert(pos >= n);
            assert(n > 0);

            auto chars = this.chars;
            const size_t len = (chars.length - pos);

            memMove(
                chars.ptr + (pos - n),
                (chars.ptr + pos),
                len
            );

            this.length = (chars.length - n);
        }

        private Char[] _expand_move(const size_t pos, const size_t n)scope return {
            assert(n > 0);

            auto chars = this.chars;
            if(pos >= chars.length)
                return this._expand(n);

            const size_t new_length = (chars.length + n);
            this.reserve(new_length);


            return ()@trusted{
                auto chars = this.chars;
                this.length = new_length;

                const size_t len = (chars.length - pos);

                memMove(
                    (chars.ptr + pos + n),
                    (chars.ptr + pos),
                    len
                );

                return (chars.ptr + pos)[0 .. n];
            }();
        }

        private Char[] _expand(const size_t n)scope return{
            const size_t old_length = this.length;
            const size_t new_length = (old_length + n);

            this.reserve(new_length);

            return ()@trusted{
                auto chars = this.chars;
                //assert(this.capacity >= new_length);
                this.length = new_length;

                return chars.ptr[old_length .. new_length];
            }();
        }

        /+package void moveTo(ref typeof(this) target)@trusted pure nothrow @nogc{
            //  Unsafe when compiling without -dip1000
            assert(&this !is &target, "source and target must not be identical");

            (ref source)@trusted pure{
                target.release();
                static if(!hasStatelessAllocator)
                    target.allocator = move(source.allocator);


                if(this._sso)
                    target._short = source._short;
                else
                    target._long = source._long;

                source._short.setShort();
                source._short.length = 0;

                /+memCopy(target._raw.ptr, source._raw.ptr, _raw.length); //target._raw[] = source._raw[];
                source._short.setShort();
                source._short.length = 0;+/
            }(this);
        }+/

        private static void moveEmplaceImpl(ref typeof(this) source, ref typeof(this) target)@trusted pure nothrow @nogc{
            //  Unsafe when compiling without -dip1000
            assert(&source !is &target, "source and target must not be identical");

            ()@trusted{
                static if(hasStatelessAllocator == false)
                    target.allocator = source.allocator;


                memCopy(target._raw.ptr, source._raw.ptr, _raw.length); //target._raw[] = source._raw[];
                source._short.setShort();
                source._short.length = 0;
            }();
        }

    }
}



//mem[move|copy]
private{
    void memMove(T)(scope T* target, scope const(T)* source, size_t length)@trusted{
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

    void memCopy(T)(scope T* target, scope const(T)* source, size_t length)@trusted{
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
}


//local traits:
package {

    //Constructable:
    template isMoveConstructable(alias from, To){
        import std.traits : CopyTypeQualifiers;

        alias From = typeof(from);
        alias FromAllcoator = CopyTypeQualifiers!(From, From.Allocator);
        alias ToAllcoator = CopyTypeQualifiers!(To, To.Allocator);

        enum bool isMoveConstructable = true
            && !__traits(isRef, from)
            && is(immutable From.Char == immutable To.Char)
            && (From.MinimalCapacity == To.MinimalCapacity)
            && is(immutable From.Allocator == immutable To.Allocator)
            && is(CopyTypeQualifiers!(From, From.Char)*: CopyTypeQualifiers!(To, To.Char)*)
            &&(false
                || From.hasStatelessAllocator //&& To.hasStatelessAllocator
                || is(typeof((FromAllcoator f){ToAllcoator t = move(f);}))
            );
    }
    template isCopyConstructable(alias from, To){
        import std.traits : CopyTypeQualifiers;

        alias From = typeof(from);
        alias FromAllcoator = CopyTypeQualifiers!(From, From.Allocator);
        alias ToAllcoator = CopyTypeQualifiers!(To, To.Allocator);

        enum bool isCopyConstructable = true
            && is(immutable From.Allocator == immutable To.Allocator)
            &&(false
                || From.hasStatelessAllocator //&& To.hasStatelessAllocator
                || is(typeof((ref FromAllcoator f){ToAllcoator t = f;}))
            );
    }
    template isConstructable(alias from, To){
        enum bool isConstructable = false
            || isCopyConstructable!(from, To)
            || isMoveConstructable!(from, To);
    }

    //Assignable:
    template isAssignable(From, To){
        import std.traits : isMutable;
        enum bool isAssignable = isMutable!To
            && isConstructable!(From, To);
    }

    //Allocator traits:
    template hasMoveConstructableAllocator(alias from, To){
        import core.lifetime : move;
        import std.traits : CopyTypeQualifiers;

        alias From = typeof(from);
        alias F = CopyTypeQualifiers!(From, From.Allocator);
        alias T = CopyTypeQualifiers!(To, To.Allocator);

        enum bool hasMoveConstructableAllocator = true
            && !__traits(isRef, from)
            && is(F : T)
            && is(typeof((F f){T t = move(f);}));
    }
    template hasMoveAssignableAllocator(alias from, To){
        import core.lifetime : move;
        import std.traits : CopyTypeQualifiers;

        alias From = typeof(from);
        alias F = CopyTypeQualifiers!(From, From.Allocator);
        alias T = CopyTypeQualifiers!(To, To.Allocator);

        enum bool hasMoveAssignableAllocator = true
            && !__traits(isRef, from)
            && is(F : T)
            && is(typeof((F f, ref T t){t = move(f);}));
    }
    template hasCopyConstructableAllocator(alias from, To){
        import std.traits : CopyTypeQualifiers;

        alias From = typeof(from);
        alias F = CopyTypeQualifiers!(From, From.Allocator);
        alias T = CopyTypeQualifiers!(To, To.Allocator);

        enum bool hasCopyConstructableAllocator = true
            && is(F : T)
            && is(typeof((ref F f){T t = f;}));
    }
    template hasCopyAssignableAllocator(alias from, To){
        import std.traits : CopyTypeQualifiers;

        alias From = typeof(from);
        alias F = CopyTypeQualifiers!(From, From.Allocator);
        alias T = CopyTypeQualifiers!(To, To.Allocator);

        enum bool hasCopyAssignableAllocator = true
            && is(F : T)
            && is(typeof((ref F f, ref T t){t = f;}));
    }

}


//encoding:
package{

    size_t encodedLength(_Char, From)(const scope From from)pure nothrow @nogc @safe
    if(isSomeChar!_Char && isSomeChar!From){
        return codeLength!_Char(from);
    }

    size_t encodedLength(_Char, From)(scope const(From)[] from)pure nothrow @nogc @safe
    if(isSomeChar!_Char && isSomeChar!From){
        static if(_Char.sizeof == From.sizeof){
            return from.length;
        }
        else static if(_Char.sizeof < From.sizeof){
            size_t result = 0;

            foreach(const From c; from[]){
                result += c.encodedLength!_Char;
            }

            return result;
        }
        else{
            static assert(_Char.sizeof > From.sizeof);

            size_t result = 0;

            while(from.length){
                result += decode(from).encodedLength!_Char;
            }

            return result;
        }

    }

    size_t encodedLength(_Char, From)(const From from)pure nothrow @nogc @safe
    if(isSomeChar!_Char && isIntegral!From){
        import std.math : log10, abs;

        if(from == 0)
            return 1;

        return cast(size_t)(cast(int)(log10(abs(from))+1) + (from < 0 ? 1 : 0));

    }



    size_t encodeTo(_Char, From)(scope const(From)[] from, scope _Char[] to, const size_t count = 1)pure nothrow @nogc
    if(isSomeChar!_Char && isSomeChar!From){

        if(count == 0)
            return 0;

        assert(from.encodedLength!_Char * count <= to.length);

        debug const predictedEncodedLength = encodedLength!_Char(from);

        static if(_Char.sizeof == From.sizeof){

            const size_t len = from.length;
            ()@trusted{
                assert(to.length >= len);
                assert(from.length <= len);
                memCopy(to.ptr, from.ptr, len); //to[0 .. len] = from[];
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
                memCopy(to.ptr + len, to.ptr, len); //to[0 .. len] = from[];
            }();
            to = to[len .. $];
        }

        return (len * count);
    }

    size_t encodeTo(_Char, From)(const From from, scope _Char[] to, const size_t count = 1)pure nothrow @nogc
    if(isSomeChar!_Char && isSomeChar!From){

        if(count == 0)
            return 0;

        assert(from.encodedLength!_Char * count <= to.length);

        debug const predictedEncodedLength = encodedLength!_Char(from);

        static if(_Char.sizeof == From.sizeof){
            enum size_t len = 1;

            assert(count <= to.length);
            for(size_t i = 0; i < count; ++i){
                to[i] = from;
            }
        }
        else{
            const size_t len = dchar(from).encode(to[]);

            for(size_t i = 1; i < count; ++i){
                //to[len .. len * 2] = to[0 .. len];
                ()@trusted{
                    assert(to.length >= (len * 2));
                    memCopy(to.ptr + len, to.ptr, len); //to[0 .. len] = from[];
                }();
                to = to[len .. $];
            }

            assert(encodedLength!_Char(from) == len);
        }

        debug assert(predictedEncodedLength == len);

        return (len * count);
    }

    size_t encodeTo(_Char, From)(const From from, scope _Char[] to, const size_t count = 1)pure nothrow @nogc @safe
    if(isSomeChar!_Char && isIntegral!From){
        import std.conv : toChars;

        if(count == 0)
            return 0;

        auto ichars = toChars(from + 0);

        assert(encodedLength!_Char(from) == ichars.length);

        for(size_t c = 0; c < count; ++c){
            for(size_t i = 0; i < ichars.length; ++i)
                to[c+i] = ichars[i];
        }

        return (ichars.length * count);


    }
}
