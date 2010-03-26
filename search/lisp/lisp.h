#ifndef LISP_H
#define LISP_H

#define		U_CHAR		unsigned char
#define 	BUFSIZE		1025

#define 	FALSE		((int)(0))
#define 	TRUE		(!(FALSE))

#define 	CONS		0
#define 	ATOM		1
#define 	NIL		((CELL *)(NULL))

#define 	COMMENTCHAR	';'
#define 	BPARENTHESIS	'('
#define 	BPARENTHESIS2	'<'
#define 	BPARENTHESIS3	'['
#define 	EPARENTHESIS	')'
#define 	EPARENTHESIS2	'>'
#define 	EPARENTHESIS3	']'
#define 	SCANATOM	"%[^(;) \n\t]"
#define 	NILSYMBOL	"NIL"

#define		BLOCKSIZE	16384

#define		Consp(x)	(!Lisp_Null(x) && (_Tag(x) == CONS))
#define		Atomp(x)	(!Lisp_Null(x) && (_Tag(x) == ATOM))
#define		_Tag(cell)	(((CELL *)(cell))->tag)
#define		_Car(cell)	(((CELL *)(cell))->value.cons.car)
#define		_Cdr(cell)	(((CELL *)(cell))->value.cons.cdr)
#define		Lisp_Null(cell)	((cell) == NIL)
#define		new_cell()	(cons(NIL, NIL))
#define		Eq(x, y)	(x == y)
#define		_Atom(cell)	(((CELL *)(cell))->value.atom)

#define		EOA		((char *)(-1))	/* end of arguments */

enum		_ExitCode 	{ NormalExit, 
				       SystemError, OpenError, AllocateError, 
				       GramError, DicError, ConnError,  
				       ConfigError, ProgramError,
				       SyntaxError, UnknownId, OtherError };

/* <car> 部と <cdr> 部へのポインタで表現されたセル */
typedef		struct		_LISP_BIN {
     void		*car;			/* address of <car> */
     void		*cdr;			/* address of <cdr> */
} LISP_BIN;

/* <BIN> または 文字列 を表現する完全な構造 */
typedef		struct		_CELL {
     int		tag;			/* tag of <cell> */
                                                /*   0: cons     */
                                                /*   1: atom     */
     union {
	  LISP_BIN		cons;
	  U_CHAR	*atom;
     } value;
} CELL;

/* "malloc" の回数を減少させるため，一定のメモリ領域を確保するテーブル */
typedef		struct		_CELLTABLE {
     void		*pre;
     void		*next;
     int		max;
     int		n;
     CELL		*cell;
} CELLTABLE;

/*
extern "C" int s_feof(FILE *fp);
extern "C" CELL *s_read(FILE *fp);
extern "C" CELL *car(CELL *cell);
extern "C" CELL *cdr(CELL *cell);
extern "C" CELL *cons(void *car, void *cdr);
extern "C" int length(CELL *list);
extern "C" void error_in_lisp(void);
*/

#endif
