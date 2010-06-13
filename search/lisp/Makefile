CFLAGS = -fPIC -O3

all: lisp.a

lisp.a: lisp.o
	ar r $@ $<

clean:
	rm -f lisp.a lisp.o
