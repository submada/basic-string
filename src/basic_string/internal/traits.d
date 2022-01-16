module basic_string.internal.traits;


import std.range : isInputRange, ElementEncodingType;
import std.traits : isArray, isSomeChar;


public enum bool isRef(alias var) = false
    || __traits(isRef, var)
    || __traits(isOut, var);

enum isCharArray(T) = true
    && is(T : C[N], C, size_t N)
    && isSomeChar!C;

template isInputCharRange(T){

    enum bool isInputCharRange = true
        && isSomeChar!(ElementEncodingType!T)
        && (isInputRange!T || isArray!T);
}



//min/max:
version(D_BetterC){

    public auto min(A, B)(auto ref A a, auto ref B b){
        return (a < b)
            ? a
            : b;
    }
    public auto max(A, B)(auto ref A a, auto ref B b){
        return (a > b)
            ? a
            : b;
    }
}
else{
    public import std.algorithm.comparison :  min, max;
}
