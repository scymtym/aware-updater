LISP ?= sbcl
QUICKLISP_DIRECTORY ?= $HOME/quicklisp

.PHONY: all clean

binary=updater

all: $(binary)

$(binary): updater.lisp
	$(LISP) --noinform --disable-debugger --no-userinit \
	  --load $(QUICKLISP_DIRECTORY)/setup.lisp          \
	  --load updater.lisp                               \
	  --load secrets.lisp                               \
	  --eval '(sb-ext:save-lisp-and-die "updater" :executable t :toplevel (quote cse.aware.updater:main) :compression t)'

clean:
	rm -f $(binary)
