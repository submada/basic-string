# BasicString
## C++-style string for D using `std.experimental.allocator`.

The `BasicString` is the generalization of struct string for character type `char`, `wchar` and `dchar`.

## Features
`Allocator` is template argument instead of using `theAllocator` so
that string can be used in `@nogc` code. Default allocator is `Mallocator`.

`BasicString` use Small String Optimization (SSO)

Works with `pure`, `@safe`, `@nogc` and `nothrow`.

Compatible with `-betterC` and `-dip1000`.

Does not rely on runtime type information (`TypeInfo`).

## Documentation
https://submada.github.io/basic_string

## Example

```d
pure nothrow @safe @nogc unittest {
  import std.experimental.allocator.mallocator : Mallocator;

  alias String = BasicString!(
    char,               //character type
    Mallocator,         //allocator type (can be stateless or with state)
    32                  //additional padding to increas max size of small string (small string does not allocate memory).
  );

  //copy:
  {
    String a = "123";
    String b = a;
    
    a = "456"d;
    
    assert(a == "456");
    assert(b == "123");
  }
  
  
  //append:
  {
    String str = "12";

    str.append("34");   //same as str += "34"
    str.append("56"w);  //same as str += "56"w
    str.append(7);      //same as str += 7;
    str.append('8');

    assert(str == "12345678");

    str.clear();

    assert(str.empty);

  }

  //erase:
  {
    String str = "123456789";

    str.erase(2, 2);

    assert(str == "1256789");
  }

  //insert:
  {
    String str = "123456789";

    str.insert(1, "xyz");

    assert(str == "1xyz23456789");
  }

  //replace:
  {
    String str = "123456789";

    str.replace(1, 2, "xyz");

    assert(str == "1xyz456789");
  }

  //replace:
  ()@trusted{
    String str = "123456789";

    string dstr = str[];

    assert(str == dstr);
  }();
}
```
