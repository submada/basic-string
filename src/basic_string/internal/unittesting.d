module basic_string.internal.unittesting;

import std.meta : AliasSeq;

import basic_string;
import basic_string.internal.mallocator;


version(basic_string_unittest)
struct TestStatelessAllocator(bool Realloc){
    import std.experimental.allocator.common : stateSize;

    private struct Allocation{
        void[] alloc;
        long count;


        this(void[] alloc, long c)pure nothrow @safe @nogc{
            this.alloc = alloc;
            this.count = c;
        }
    }

    private static Allocation[] allocations;
    private static void[][] bad_dealocations;


    private void add(void[] b)scope nothrow @trusted{
        if(b.length == 0)
            return;

        foreach(ref a; allocations){
            if(a.alloc.ptr is b.ptr && a.alloc.length == b.length){
                a.count += 1;
                return;
            }
        }

        allocations ~= Allocation(b, 1);
    }

    private void del(void[] b)scope nothrow @trusted{
        foreach(ref a; allocations){
            if(a.alloc.ptr is b.ptr && a.alloc.length == b.length){
                a.count -= 1;
                return;
            }
        }

        bad_dealocations ~= b;
    }


    import std.experimental.allocator.common : platformAlignment;

    public enum uint alignment = platformAlignment;

    public void[] allocate(size_t bytes)scope @trusted nothrow{
        auto data = Mallocator.instance.allocate(bytes);
        if(data.length == 0)
            return null;

        this.add(data);

        return data;
    }

    public bool deallocate(void[] b)scope @system nothrow{
        const result = Mallocator.instance.deallocate(b);
        assert(result);

        this.del(b);

        return result;

    }

    public bool reallocate(ref void[] b, size_t s)scope @system nothrow{
        static if(Realloc){
            void[] old = b;

            const result = Mallocator.instance.reallocate(b, s);

            this.del(old);
            this.add(b);

            return result;

        }
        else return false;
    }


    public bool empty()scope const nothrow @safe @nogc{
        import std.algorithm : all;

        return true
            && bad_dealocations.length == 0
            && allocations.all!((a) => a.count == 0);

    }

    static typeof(this) instance;
}

version(basic_string_unittest)
class TestStateAllocator(bool Realloc){
    import std.experimental.allocator.common : stateSize;

    private struct Allocation{
        void[] alloc;
        long count;


        this(void[] alloc, long c)pure nothrow @safe @nogc{
            this.alloc = alloc;
            this.count = c;
        }
    }

    private Allocation[] allocations;
    private void[][] bad_dealocations;


    private void add(void[] b)scope nothrow @trusted{
        if(b.length == 0)
            return;

        foreach(ref a; allocations){
            if(a.alloc.ptr is b.ptr && a.alloc.length == b.length){
                a.count += 1;
                return;
            }
        }

        allocations ~= Allocation(b, 1);
    }

    private void del(void[] b)scope nothrow @trusted{
        foreach(ref a; allocations){
            if(a.alloc.ptr is b.ptr && a.alloc.length == b.length){
                a.count -= 1;
                return;
            }
        }

        bad_dealocations ~= b;
    }


    import std.experimental.allocator.common : platformAlignment;

    public enum uint alignment = platformAlignment;

    public void[] allocate(size_t bytes)scope @trusted nothrow{
        auto data = Mallocator.instance.allocate(bytes);
        if(data.length == 0)
            return null;

        this.add(data);

        return data;
    }

    public bool deallocate(void[] b)scope @system nothrow{
        const result = Mallocator.instance.deallocate(b);
        assert(result);

        this.del(b);

        return result;

    }

    public bool reallocate(ref void[] b, size_t s)scope @system nothrow{
        static if(Realloc){
            void[] old = b;

            const result = Mallocator.instance.reallocate(b, s);

            this.del(old);
            this.add(b);

            return result;

        }
        else return false;
    }


    public bool empty()scope const nothrow @safe @nogc{
        import std.algorithm : all;

        return true
            && bad_dealocations.length == 0
            && allocations.all!((a) => a.count == 0);

    }
}




version(basic_string_unittest){
    private auto trustedSlice(S)(auto ref scope S str)@trusted{
        return str[];
    }
    private auto trustedSlice(S)(auto ref scope S str, size_t b, size_t e)@trusted{
        return str[b .. e];
    }
    private auto trustedSliceToEnd(S)(auto ref scope S str, size_t b)@trusted{
        return str[b .. $];
    }

    void unittest_allocator_impl(Char, Allocator)(Allocator allocator){
        alias Str = BasicString!(Char, Allocator);

        static if(Str.hasStatelessAllocator)
            alias allocatorWithState = AliasSeq!();
        else
            alias allocatorWithState = AliasSeq!(allocator);

        Str str = Str(allocatorWithState, "1");
        auto a = str.allocator;
    }

    void unittest_reserve_impl(Char, Allocator)(Allocator allocator){
        alias Str = BasicString!(Char, Allocator);

        static if(Str.hasStatelessAllocator)
            alias allocatorWithState = AliasSeq!();
        else
            alias allocatorWithState = AliasSeq!(allocator);

        ///reserve:
        Str str = Str(allocatorWithState, "1");
        assert(str.capacity == Str.MinimalCapacity);
        //----------------------------
        const size_t new_capacity = str.capacity * 2 + 1;
        str.reserve(new_capacity);
        assert(str.capacity > new_capacity);
        //----------------------------
        str.clear();
        assert(str.empty);
    }

    void unittest_resize_impl(Char, Allocator)(Allocator allocator){
        alias Str = BasicString!(Char, Allocator);

        static if(Str.hasStatelessAllocator)
            alias allocatorWithState = AliasSeq!();
        else
            alias allocatorWithState = AliasSeq!(allocator);

        ///resize:
        Str str = Str(allocatorWithState, "1");
        assert(str.capacity == Str.MinimalCapacity);
        //----------------------------
        str.resize(Str.MinimalCapacity);
        assert(str.capacity == Str.MinimalCapacity);
        assert(str.length == Str.MinimalCapacity);
        //----------------------------
        str.resize(Str.MinimalCapacity - 1, '_');
        assert(str.capacity == Str.MinimalCapacity);
        assert(str.length == Str.MinimalCapacity - 1);
        //----------------------------
        str.resize(Str.MinimalCapacity + 3, '_');
        assert(str.capacity > Str.MinimalCapacity);
        assert(str.length == Str.MinimalCapacity + 3);

    }


    void unittest_ctor_string_impl(Char, Allocator)(Allocator allocator){
        alias Str = BasicString!(Char, Allocator);

        static if(Str.hasStatelessAllocator)
            alias allocatorWithState = AliasSeq!();
        else
            alias allocatorWithState = AliasSeq!(allocator);

        static foreach(enum val; AliasSeq!(
            "0123",
            "0123456789_0123456789_0123456789_0123456789",
        ))
        static foreach(enum I; AliasSeq!(1, 2, 3, 4)){{
            static if(I == 1){
                char[val.length] s = val;
                wchar[val.length] w = val;
                dchar[val.length] d = val;
            }
            else static if(I == 2){
                immutable(char)[val.length] s = val;
                immutable(wchar)[val.length] w = val;
                immutable(dchar)[val.length] d = val;
            }
            else static if(I == 3){
                enum string s = val;
                enum wstring w = val;
                enum dstring d = val;
            }
            else static if(I == 4){
                auto s = BasicString!(char, Allocator)(allocatorWithState, val);
                auto w = BasicString!(wchar, Allocator)(allocatorWithState, val);
                auto d = BasicString!(dchar, Allocator)(allocatorWithState, val);
            }
            else static assert(0, "no impl");

            auto str1 = Str(allocatorWithState, s);
            str1 = s;
            auto str2 = Str(allocatorWithState, s.trustedSlice);
            str2 = s.trustedSlice;
            assert(str1 == str2);

            auto wstr1 = Str(allocatorWithState, w);
            wstr1 = w;
            auto wstr2 = Str(allocatorWithState, w.trustedSlice);
            wstr2 = w.trustedSlice;
            assert(wstr1 == wstr2);

            auto dstr1 = Str(allocatorWithState, d);
            dstr1 = d;
            auto dstr2 = Str(allocatorWithState, d.trustedSlice);
            dstr2 = d.trustedSlice;
            assert(dstr1 == dstr2);
        }}


    }

    void unittest_ctor_char_impl(Char, Allocator)(Allocator allocator){
        alias Str = BasicString!(Char, Allocator);

        static if(Str.hasStatelessAllocator)
            alias allocatorWithState = AliasSeq!();
        else
            alias allocatorWithState = AliasSeq!(allocator);

        static foreach(enum val; AliasSeq!(
            cast(char)'1',
            cast(wchar)'2',
            cast(dchar)'3',
        ))
        static foreach(enum I; AliasSeq!(1, 2, 3)){{
            static if(I == 1){
                char c = val;
                wchar w = val;
                dchar d = val;
            }
            else static if(I == 2){
                immutable(char) c = val;
                immutable(wchar) w = val;
                immutable(dchar) d = val;
            }
            else static if(I == 3){
                enum char c = val;
                enum wchar w = val;
                enum dchar d = val;
            }
            else static assert(0, "no impl");

            auto str = Str(allocatorWithState, c);
            str = c;

            auto wstr = Str(allocatorWithState, w);
            wstr = w;

            auto dstr = Str(allocatorWithState, d);
            dstr = d;
        }}

    }


    void unittest_shrink_to_fit_impl(Char, Allocator)(Allocator allocator){
        alias Str = BasicString!(Char, Allocator);

        static if(Str.hasStatelessAllocator)
            alias allocatorWithState = AliasSeq!();
        else
            alias allocatorWithState = AliasSeq!(allocator);

        Str str = Str(allocatorWithState, "123");
        assert(str.capacity == Str.MinimalCapacity);

        //----------------------------
        assert(str.small);
        str.resize(str.capacity * 2, 'x');
        assert(!str.small);


        const size_t cap = str.capacity;
        const size_t len = str.length;
        str.shrinkToFit();
        assert(str.length == len);
        assert(str.capacity == cap);

        str = "123";
        assert(str.length == 3);
        assert(str.capacity == cap);

        str.shrinkToFit();
        assert(str.length == 3);
        assert(str.capacity == Str.MinimalCapacity);

        //----------------------------
        str.clear();
        assert(str.empty);

    }


    void unittest_operator_plus_string_impl(Char, Allocator)(Allocator allocator){
        alias Str = BasicString!(Char, Allocator);

        static if(Str.hasStatelessAllocator)
            alias allocatorWithState = AliasSeq!();
        else
            alias allocatorWithState = AliasSeq!(allocator);

        static foreach(enum I; AliasSeq!(1, 2, 3, 4)){{
            static if(I == 1){
                auto s = BasicString!(char, Allocator)(allocatorWithState, "45");
                auto w = BasicString!(wchar, Allocator)(allocatorWithState, "67");
                auto d = BasicString!(dchar, Allocator)(allocatorWithState, "89");
            }
            else static if(I == 2){
                immutable(char)[2] s = "45";
                immutable(wchar)[2] w = "67";
                immutable(dchar)[2] d = "89";
            }
            else static if(I == 3){
                enum string s = "45";
                enum wstring w = "67";
                enum dstring d = "89";
            }
            else static if(I == 4){
                char[2] sx = ['4', '5'];
                wchar[2] wx = ['6', '7'];
                dchar[2] dx = ['8', '9'];
                char[] s = sx[];
                wchar[] w = wx[];
                dchar[] d = dx[];
            }
            else static assert(0, "no impl");


            Str str = Str(allocatorWithState, "123");
            assert(str.capacity == Str.MinimalCapacity);

            ////----------------------------
            str = (str + s);
            str = (s + str);
            str += s;
            assert(str == "451234545");

            str = (str + w);
            str = (w + str);
            str += w;
            assert(str == "674512345456767");

            str = (str + d);
            str = (d + str);
            str += d;
            assert(str == "896745123454567678989");

            //----------------------------
            str.clear();
            assert(str.empty);
        }}
    }

    void unittest_operator_plus_char_impl(Char, Allocator)(Allocator allocator){
        alias Str = BasicString!(Char, Allocator);

        static if(Str.hasStatelessAllocator)
            alias allocatorWithState = AliasSeq!();
        else
            alias allocatorWithState = AliasSeq!(allocator);

        static foreach(enum I; AliasSeq!(1, 2)){{
            static if(I == 1){
                char c = 'a';
                wchar w = 'b';
                dchar d = 'c';
            }
            else static if(I == 2){
                enum char c = 'a';
                enum wchar w = 'b';
                enum dchar d = 'c';
            }
            else static assert(0, "no impl");


            Str str = Str(allocatorWithState, "123");
            assert(str.capacity == Str.MinimalCapacity);

            ////----------------------------
            str = (str + c);
            str = (c + str);
            str += c;
            assert(str == "a123aa");

            str = (str + w);
            str = (w + str);
            str += w;
            assert(str == "ba123aabb");

            str = (str + d);
            str = (d + str);
            str += d;
            assert(str == "cba123aabbcc");

            //----------------------------
            str.clear();
            assert(str.empty);
        }}
    }


    void unittest_append_impl(Char, Allocator)(Allocator allocator){
        alias Str = BasicString!(Char, Allocator);

        static if(Str.hasStatelessAllocator)
            alias allocatorWithState = AliasSeq!();
        else
            alias allocatorWithState = AliasSeq!(allocator);

        static foreach(enum val; AliasSeq!(
            "0123",
            "0123456789_0123456789_0123456789_0123456789",
        ))
        static foreach(enum rep; AliasSeq!(
            'x',
            "",
            "a",
            "ab",
            "abcdefgh_abcdefgh_abcdefgh_abcdefgh",
        ))
        static foreach(enum size_t count; AliasSeq!(0, 1, 2, 3))
        static foreach(alias T; AliasSeq!(char, wchar, dchar)){{
            import std.traits : isArray;

            static if(isArray!(typeof(rep)))
                alias Rep = immutable(T)[];
            else
                alias Rep = T;


            Str str = Str(allocatorWithState, val);

            str.append(cast(Rep)rep, count);


            Str rep_complet = Str(allocatorWithState, null);
            for(size_t i = 0; i < count; ++i)
                rep_complet += cast(Rep)rep;

            import std.range;
            assert(str == Str.build(allocatorWithState, val, rep_complet.trustedSlice));
            //assert(str == chain(val, rep_complet[]));

        }}

    }

    void unittest_insert_impl(Char, Allocator)(Allocator allocator){
        alias Str = BasicString!(Char, Allocator);

        static if(Str.hasStatelessAllocator)
            alias allocatorWithState = AliasSeq!();
        else
            alias allocatorWithState = AliasSeq!(allocator);

        static foreach(enum val; AliasSeq!(
            "0123",
            "0123456789_0123456789_0123456789_0123456789",
        ))
        static foreach(enum rep_source; AliasSeq!(
            'x',
            "",
            "a",
            "ab",
            "abcdefgh_abcdefgh_abcdefgh_abcdefgh",
        ))
        static foreach(enum size_t count; AliasSeq!(0, 1, 2, 3))
        static foreach(alias T; AliasSeq!(char, wchar, dchar)){{
            import std.traits : isArray;

            static if(isArray!(typeof(rep_source)))
                enum immutable(T)[] rep = rep_source;
            else
                enum T rep = rep_source;


            Str rep_complet = Str(allocatorWithState, null);
            for(size_t i = 0; i < count; ++i)
                rep_complet += rep;

            {
                Str str = Str(allocatorWithState, val);

                const x = str.insert(2, rep, count);
                assert(Str(allocatorWithState, rep).length * count == x);
                assert(str == Str.build(allocatorWithState, val.trustedSlice(0, 2), rep_complet, val.trustedSliceToEnd(2)));
            }
            {
                Str str = Str(allocatorWithState, val);

                const x = str.insert(str.length, rep, count);
                assert(Str(allocatorWithState, rep).length * count == x);
                assert(str == Str.build(allocatorWithState, val, rep_complet));
            }
            {
                Str str = Str(allocatorWithState, val);

                const x = str.insert(str.length + 2000, rep, count);
                assert(Str(allocatorWithState, rep).length * count == x);
                assert(str == Str.build(allocatorWithState, val, rep_complet));
            }
            {
                Str str = Str(allocatorWithState, val);

                const x = str.insert(0, rep, count);
                assert(Str(allocatorWithState, rep).length * count == x);
                assert(str == Str.build(allocatorWithState, rep_complet, val));
            }
            //------------------------------------------------
            {
                Str str = Str(allocatorWithState, val);

                const x = str.insert((()@trusted => str.ptr + 2)(), rep, count);
                assert(Str(allocatorWithState, rep).length * count == x);
                assert(str == Str.build(allocatorWithState, val.trustedSlice(0, 2), rep_complet, val.trustedSliceToEnd(2)));
            }
            {
                Str str = Str(allocatorWithState, val);

                const x = str.insert((()@trusted => str.ptr + str.length)(), rep, count);
                assert(Str(allocatorWithState, rep).length * count == x);
                assert(str == Str.build(allocatorWithState, val, rep_complet));
            }
            {
                Str str = Str(allocatorWithState, val);

                const x = str.insert((()@trusted => str.ptr + str.length + 2000)(), rep, count);
                assert(Str(allocatorWithState, rep).length * count == x);
                assert(str == Str.build(allocatorWithState, val, rep_complet));
            }
            {
                Str str = Str(allocatorWithState, val);

                const x = str.insert((()@trusted => str.ptr)(), rep, count);
                assert(Str(allocatorWithState, rep).length * count == x);
                assert(str == Str.build(allocatorWithState, rep_complet, val));
            }
            {
                Str str = Str(allocatorWithState, val);

                const x = str.insert((()@trusted => str.ptr - 1000)(), rep, count);
                assert(Str(allocatorWithState, rep).length * count == x);
                assert(str == Str.build(allocatorWithState, rep_complet, val));
            }

        }}
    }

    void unittest_erase_impl(Char, Allocator)(Allocator allocator){
        alias Str = BasicString!(Char, Allocator);

        static if(Str.hasStatelessAllocator)
            alias allocatorWithState = AliasSeq!();
        else
            alias allocatorWithState = AliasSeq!(allocator);

        static foreach(enum val; AliasSeq!(
            "0123",
            "0123456789_0123456789_0123456789_0123456789",
        )){
            {
                Str str = Str(allocatorWithState, val);

                str.erase(2);
                //assert(str.equals_test(Str(val[0 .. 2])));
                assert(str == Str(allocatorWithState, val[0 .. 2]));
            }
            {
                Str str = Str(allocatorWithState, val);

                str.erase(1, 2);
                assert(str == Str.build(allocatorWithState, val[0 .. 1], val[3 .. $]));
            }
            {
                Str str = Str(allocatorWithState, val);

                str.erase(1, 1000);
                assert(str == Str.build(allocatorWithState, val[0 .. 1]));
            }
            {
                Str str = Str(allocatorWithState, val);

                str.erase(str.trustedSliceToEnd(2));
                assert(str == Str.build(allocatorWithState, val[0 .. 2]));
            }
            {
                Str str = Str(allocatorWithState, val);

                str.erase(str.trustedSlice(1, 3));
                assert(str == Str.build(allocatorWithState, val.trustedSlice(0, 1), val.trustedSliceToEnd(3)));
            }
            {
                Str str = Str(allocatorWithState, val);

                str.erase((()@trusted => str.ptr + 2)());
                assert(str == Str(allocatorWithState, val.trustedSlice(0, 2)));
            }
        }

        ///downsize (erase):
        {
            Str str = Str(allocatorWithState, "123");
            assert(str.length == 3);

            //----------------------------
            str.erase(3);
            assert(str.length == 3);

            str.erase(1000);
            assert(str.length == 3);

            str.erase(1);
            assert(str.length == 1);

            //----------------------------
            const size_t new_length = str.capacity * 2;
            str.resize(new_length);
            assert(str.capacity >= new_length);
            assert(str.length == new_length);

            str.erase(3);
            assert(str.length == 3);

            str.erase(1000);
            assert(str.length == 3);

            str.erase(1);
            assert(str.length == 1);

            //----------------------------
            str.clear();
            assert(str.empty);
        }
    }

    void unittest_replace_impl(Char, Allocator)(Allocator allocator){
        alias Str = BasicString!(Char, Allocator);

        static if(Str.hasStatelessAllocator)
            alias allocatorWithState = AliasSeq!();
        else
            alias allocatorWithState = AliasSeq!(allocator);

        static foreach(enum val; AliasSeq!(
            "0123",
            "0123456789_0123456789_0123456789_0123456789",
        ))
        static foreach(enum rep_source; AliasSeq!(
            'x',
            "",
            "a",
            "ab",
            "abcdefgh_abcdefgh_abcdefgh_abcdefgh",
        ))
        static foreach(enum size_t count; AliasSeq!(0, 1, 2, 3))
        static foreach(alias T; AliasSeq!(char, wchar, dchar)){{
            import std.traits : isArray;

            static if(isArray!(typeof(rep_source)))
                enum immutable(T)[] rep = rep_source;
            else
                enum T rep = rep_source;


            Str rep_complet = Str(allocatorWithState, null);
            for(size_t i = 0; i < count; ++i)
                rep_complet += rep;

            {
                Str str = Str(allocatorWithState, val);

                str.replace(1, 2, rep, count);
                //debug writeln(val, ": ", str[], " vs ", val[0 .. 1], " | ", rep_complet[], " | ", val[3 .. $]);
                //assert(str[] == Str.build(val[0 .. 1], rep_complet[], val[3 .. $]));
            }
            {
                Str str = Str(allocatorWithState, val);

                str.replace(1, val.length - 1, rep, count);
                //assert(str[] == Str.build(val[0 .. 1], rep_complet[]));
            }
            {
                Str str = Str(allocatorWithState, val);

                str.replace(1, val.length + 2000, rep, count);
                //assert(str[] == Str.build(val[0 .. 1], rep_complet[]));
            }
            //------------------------
            {
                Str str = Str(allocatorWithState, val);

                str.replace((()@trusted => str[1 .. $ - 1])(), rep, count);
                //assert(str[] == Str.build(val[0 .. 1], rep_complet[], val[$ - 1 .. $]));
            }
            {
                Str str = Str(allocatorWithState, val);

                str.replace((()@trusted => str[1 ..  $])(), rep, count);
                //assert(str[] == Str.build(val[0 .. 1], rep_complet[]));
            }
            {
                Str str = Str(allocatorWithState, val);

                str.replace((()@trusted => str.ptr[1 .. str.length + 2000])(), rep, count);
                //assert(str[] == Str.build(val[0 .. 1], rep_complet[]));
            }

        }}
    }


    void unittest_output_range_impl(Char, Allocator)(Allocator allocator){
        alias Str = BasicString!(Char, Allocator);

        static if(Str.hasStatelessAllocator)
            alias allocatorWithState = AliasSeq!();
        else
            alias allocatorWithState = AliasSeq!(allocator);

        static foreach(alias T; AliasSeq!(char, wchar, dchar)){{
            import std.range : only;
            import std.algorithm.mutation : copy;

            {
                Str str = only(
                    cast(immutable(T)[])"a",
                    cast(immutable(T)[])"bc",
                    cast(immutable(T)[])"",
                    cast(immutable(T)[])"d"
                ).copy(Str(allocatorWithState));

            }
            {
                Str str = only(
                    cast(T)'a',
                    cast(T)'b',
                    cast(T)'c'
                ).copy(Str(allocatorWithState));

                assert(str == Str(allocatorWithState, "abc"));

            }
        }}
    }

}


version(basic_string_unittest)
void unittest_impl(Char, Allocator)(Allocator allocator){
    unittest_allocator_impl!Char(allocator);

    unittest_reserve_impl!Char(allocator);
    unittest_resize_impl!Char(allocator);

    unittest_ctor_string_impl!Char(allocator);
    unittest_ctor_char_impl!Char(allocator);

    unittest_shrink_to_fit_impl!Char(allocator);

    unittest_operator_plus_string_impl!Char(allocator);
    unittest_operator_plus_char_impl!Char(allocator);

    unittest_append_impl!Char(allocator);
    unittest_insert_impl!Char(allocator);
    unittest_erase_impl!Char(allocator);
    unittest_replace_impl!Char(allocator);

    unittest_output_range_impl!Char(allocator);

}



version(basic_string_unittest)
void unittest_impl(Allocator)(Allocator allocator = Allocator.init){
    import std.stdio : writeln;
    import std.range : only;
    import std.experimental.allocator.common : stateSize;

    static foreach(alias Char; AliasSeq!(char, wchar, dchar))
        unittest_impl!Char(allocator);

}

version(basic_string_unittest)
@nogc @safe pure nothrow unittest{
    unittest_impl!Mallocator();
}

version(basic_string_unittest)
nothrow unittest{
    version(D_BetterC){}
    else{
        static foreach(enum bool Realloc; [false, true]){
            {
                alias AX = TestStatelessAllocator!Realloc;

                assert(AX.instance.empty);

                unittest_impl!AX();

                assert(AX.instance.empty);
            }

            {
                alias AX = TestStateAllocator!Realloc;

                auto allocator = new AX;


                assert(allocator.empty);

                unittest_impl(allocator);

                assert(allocator.empty);


                //unittest_impl(allocator);

            }

            {
                alias AX = TestStateAllocator!Realloc;
                auto allocator = new AX;

                assert(allocator.empty);

                {
                    alias Str = BasicString!(char, AX);

                    //Str b;
                    //auto a = Str(allocator, "0123456789_0123456789_0123456789_");

                }

                assert(allocator.empty);

            }
        }
    }
}


