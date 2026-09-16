# hyDe

`hyde` is a static site generator written in D, meant to be a lightweight replacement of [Jekyll](https://github.com/jekyll/jekyll).


```
$ hyde --help
   /|     }/>          __ _dhyyy#%%\     Y&dd#%=$=/|Y
  |%&     | y&;     &;/^</Y&&#%   %YY| <y##//      7
  ;&%    ;&  \Y_   |#&;   {%/      \#\  |;/h\_
  :%___=%&|   \D__y#;    {%%        |D /&|&/%#?&?:;|
<=%%#?^&#HY    |h%&;:     |%      |E   \%/        \|
 /%/    H%/      y/      |%y    /%/   /%%
 ||     |E      /#y       ||H%/y     _|%&$%&%##|Yh\
;/       %/   /D}        |%D/y       y/          y&
             y^         <y/

Using hyde:
  hyde build --site <path>
  hyde --help
  hyde --version

```

## Building hyde

Build `hyde` with `dub`:

```
$ dub build --build=release
```

This creates a directory `./build` containing an executable `hyde`.

## Building the website

From the `hyde` directory:

```
$ build/hyde build --site path/to/site
```

This creates a `public` directory in the site directory with the formatted HTML files.