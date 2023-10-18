Build
=====

1. Install [SBCL](http://sbcl.org)

   On Debian-based distributions like Ubuntu,

   ```bash
   apt install sbcl make
   ```

   might suffice.

2. Install [Quicklisp](https://beta.quicklisp.org)

   ```bash
   wget https://beta.quicklisp.org/quicklisp.lisp
   sbcl --load quicklisp.lisp --eval '(quicklisp-quickstart:install :path "SOMEWHERE/quicklisp/")' --quit
   ```

3. Build

   ```bash
   LISP=sbcl QUICKLISP_DIRECTORY=SOMEWHERE/quicklisp make
   ```
