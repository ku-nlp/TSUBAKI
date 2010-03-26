#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lisp.h"

int		LineNo = 0;
int		LineNoForError = 0;

U_CHAR		Buffer[BUFSIZE];
CELL		_TmpCell;
CELL		*TmpCell = &_TmpCell;
CELLTABLE	*CellTbl = NULL;

CELLTABLE	CellTbl_save;

static int (*my_getc)(FILE *fp) = fgetc;
static int (*my_ungetc)(int c, FILE *fp) = ungetc;

CELL *s_read_atom(FILE *fp);
CELL *s_read_car(FILE *fp);
CELL *s_read_cdr(FILE *fp);
CELL *_s_print_(FILE *fp, CELL *cell);
CELL *s_print(FILE *fp, CELL *cell);
CELL *_s_print_cdr(FILE *fp, CELL *cell);
void *lisp_alloc(int n);


CELL *s_read_atom_string (char **chp);
CELL *s_read_car_string (char **chp);
CELL *s_read_cdr_string (char **chp);
CELL *s_read_from_string (char **sexp);

/*
------------------------------------------------------------------------------
	local error processing
------------------------------------------------------------------------------
*/

void my_exit(int exit_code)
{
     fprintf(stderr, "exit(%d)\n", exit_code);
     exit(exit_code);
}

void error_in_lisp(void)
{
     fprintf(stderr, "\nparse error between line %d and %d.\n", 
	     LineNoForError, LineNo);
     my_exit(DicError);
}

void error_in_program(void)
{
     fprintf(stderr, "\n\"ifnextchar\" returns an unexpected code.\n");
     my_exit(ProgramError);
}

/*
------------------------------------------------------------------------------
	FUNCTION
	<s_feof>:
	after skipping "whitespace" , return TRUE if fp points to EOF
------------------------------------------------------------------------------
*/

int s_feof(FILE *fp) /* bug fixed by kurohashi on 92/4/25 */
{
  int	code, c;

  if (s_feof_comment(fp) == EOF) {
    code = TRUE;
  } else {
    if ((c = my_getc(fp)) == EOF) {
      code = TRUE;
    } else {
      if ( (U_CHAR)c == '\n') {
	LineNo++;
	code = s_feof(fp);
      } else if ( (U_CHAR)c == ' ' || (U_CHAR)c == '\t') {
	code = s_feof(fp);
      } else {
	my_ungetc(c, fp);
	code = FALSE;
      }
    }
  }
  return code;
}

int s_feof_comment(FILE *fp)
{
     int	n;

     if ((n = ifnextchar(fp, (int)COMMENTCHAR)) == TRUE) {
	  while (my_getc(fp) != '\n' && !feof(fp)) {}
	  LineNo++;
	  return s_feof_comment(fp);
     }

     return n;
}

/*
------------------------------------------------------------------------------
	FUNCTION
	<make_cell>: make a new cell
------------------------------------------------------------------------------
*/

CELL *make_cell(void)
{
    return((CELL *)lisp_alloc(sizeof(CELL)));
}

/*
------------------------------------------------------------------------------
	FUNCTION
	<tmp_atom>: use <TmpCell>
------------------------------------------------------------------------------
*/

CELL *tmp_atom(U_CHAR *atom)

{
     _Tag(TmpCell) = ATOM;
     _Atom(TmpCell) = atom;

     return TmpCell;
}

/*
------------------------------------------------------------------------------
	FUNCTION
	<cons>: make <cons> from <car> & <cdr>
------------------------------------------------------------------------------
*/

CELL *cons(void *car, void *cdr)
{
     CELL *cell;

     cell = make_cell();
     _Tag(cell) = CONS;
     _Car(cell) = car;
     _Cdr(cell) = cdr;

     return cell;
}

/*
------------------------------------------------------------------------------
	FUNCTION
	<car>: take <car> from <cons>
------------------------------------------------------------------------------
*/

CELL *car(CELL *cell)
{
     if (Consp(cell))
	  return _Car(cell);
     else if (Lisp_Null(cell))
	  return NIL;
     else {
	  s_print(stderr, cell);
	  fprintf(stderr, "is not list. in <car>\n");
	  error_in_lisp();
     }
     return NIL;
}

/*
------------------------------------------------------------------------------
	FUNCTION
	<cdr>: take <cdr> from <cons>
------------------------------------------------------------------------------
*/

CELL *cdr(CELL *cell)
{
    if (Consp(cell))
      return _Cdr(cell);
    else if (Lisp_Null(cell))
      return NIL;
    else {
	s_print(stderr, cell);
	fprintf(stderr, "is not list. in <cdr>\n");
	error_in_lisp();
    }
    return NIL;
}

/*
------------------------------------------------------------------------------
	FUNCTION
	<equal>:
------------------------------------------------------------------------------
*/

int equal(void *x, void *y)
{
     if (Eq(x, y)) return TRUE;
     else if (Lisp_Null(x) || Lisp_Null(y)) return FALSE;
     else if (_Tag(x) != _Tag(y)) return FALSE;
     else if (_Tag(x) == ATOM)	  return !strcmp(_Atom(x), _Atom(y));
     else if (_Tag(x) == CONS)
	  return (equal(_Car(x), _Car(y)) && equal(_Cdr(x), _Cdr(y)));
     else
	  return FALSE;
}

int length(CELL *list)
{
     int	i;

     for (i = 0; Consp(list); i++) {
	  list = _Cdr(list);
     }

     return i;
}

/*
------------------------------------------------------------------------------
	FUNCTION
	<ifnextchar>: if next char is <c> return 1, otherwise return 0
------------------------------------------------------------------------------
*/

int ifnextchar(FILE *fp, int i)
{
     int 	c;

     do {
	  c = my_getc(fp);
	  if (c == '\n') LineNo++;
     } while (c == ' ' || c == '\t' || c == '\n' || c == '\r');

     if (c == EOF) return EOF;

     if (i == c) 
	  return TRUE;
     else {
	  my_ungetc(c, fp);
	  return FALSE;
     }
}

/*
------------------------------------------------------------------------------
	FUNCTION
	<comment>: skip comment-line(s)
------------------------------------------------------------------------------
*/

int comment(FILE *fp)
{
     int	n;

     if ((n = ifnextchar(fp, (int)COMMENTCHAR)) == TRUE) {
	  while (my_getc(fp) != '\n' && !feof(fp)) {}
	  LineNo++;
	  comment(fp);
     } else if (n == EOF) {
	 ;
     }

     return n;
}

/*
------------------------------------------------------------------------------
	FUNCTION
	<s_read>: read S-expression
------------------------------------------------------------------------------
*/

CELL *s_read(FILE *fp)
{
     int n;

     if ((n = ifnextchar(fp, (int)BPARENTHESIS)) == TRUE) {
	  return s_read_car(fp);
     } else if (n == FALSE) {
	  return s_read_atom(fp);
     }

     if (n == EOF) error_in_lisp();
     else	   error_in_program();

     return NIL;
}

int myscanf(FILE *fp, U_CHAR *cp)
{
    int code;

    code = my_getc(fp);
    if ( dividing_code_p(code) )
      return 0;
    else if ( code == EOF )
      return EOF;
    else if ( code == '"' ) {
	*cp++ = code;
	while ( 1 ) {
	    code = my_getc(fp);
	    if ( code == EOF )
	      error_in_lisp();
	    else if ( code == '"' ) {
		*cp++ = code;
		*cp++ = '\0';
		return 1;
	    }
#ifndef _WIN32
	    else if ( code == '\\' ) {
		*cp++ = code;
		if ( (code = my_getc(fp)) == EOF ) 
		    error_in_lisp();
		*cp++ = code;
	    }
#endif
	    else {
		*cp++ = code;
	    }
	}
    }
    else {
	*cp++ = code;
#ifndef _WIN32
	if (code == '\\') 
	    *(cp-1) = my_getc(fp); /* kuro on 12/01/94 */
#endif
	while ( 1 ) {
	    code = my_getc(fp);
	    if ( dividing_code_p(code) || code == EOF ) {
		*cp++ = '\0';
		my_ungetc(code, fp);
		return 1;
	    }
	    else {
		*cp++ = code;
#ifndef _WIN32
		if (code == '\\') 
		    *(cp-1) = my_getc(fp); /* kuro on 12/01/94 */
#endif
	    }
	}
    }
}


int myscanf_string (char **chp, U_CHAR *cp)
{
    int code;

    code = (int)*(chp)[0];
    if ( dividing_code_p(code) )
      return 0;
    else if ( code == EOF )
      return EOF;
    else if ( code == '"' ) {
	*cp++ = code;
	while ( 1 ) {
	    ++*(chp);
	    code = (int)*(chp)[0];
	    if ( code == '\0' )
	      error_in_lisp();
	    else if ( code == '"' ) {
		*cp++ = code;
		*cp++ = '\0';
		return 1;
	    }
	    else {
		*cp++ = code;
	    }
	}
    }
    else {
	*cp++ = code;
	while ( 1 ) {
	    ++*(chp);
	    code = (int)*(chp)[0];
	    if ( dividing_code_p(code) || code == '\0' ) {
		*cp++ = '\0';
//		my_ungetc(code, fp);
		return 1;
	    }
	    else {
		*cp++ = code;
	    }
	}
    }
}


int dividing_code_p(int code)
{
    switch (code) {
      case '\n': case '\r': case '\t': case ';': case ' ':
      case BPARENTHESIS:
      case EPARENTHESIS:
	return 1;
      default:
	return 0;
    }
}

CELL *s_read_atom(FILE *fp)
{
     CELL *cell;
     U_CHAR *c;
     int n;

     comment(fp);

     if (((n = myscanf(fp, Buffer)) == 0) || (n == EOF)) {
	  error_in_lisp();
     }

     if (!strcmp(Buffer, NILSYMBOL)) {
	  cell = NIL;
     } else {
	  cell = new_cell();
	  _Tag(cell) = ATOM;
	  c = (U_CHAR *)lisp_alloc(sizeof(U_CHAR) * (strlen(Buffer)+1));
	  strcpy(c, Buffer);
	  _Atom(cell) = c;
     }

     return cell;
}

CELL *s_read_car(FILE *fp)
{
     CELL	*cell;
     int	n;

     comment(fp);

     if ((n = ifnextchar(fp, (int)EPARENTHESIS)) == TRUE) {
	  cell = (CELL *)NIL;
	  return cell;
     } else if (n == FALSE) {
	  cell = new_cell();
	  _Car(cell) = s_read(fp);
	  _Cdr(cell) = s_read_cdr(fp);
	  return cell;
     }

     if (n == EOF) error_in_lisp();
     else          error_in_program();

     return NIL;
}

CELL *s_read_cdr(FILE *fp)
{
     CELL	*cell;
     int	n;

     comment(fp);
     if ((n = ifnextchar(fp, (int)EPARENTHESIS)) == TRUE) {
	  cell = (CELL *)NIL;
	  return cell;
     } else if (n == FALSE) {
	  cell = s_read_car(fp);
	  return cell;
     }

     if (n == EOF) error_in_lisp();
     else          error_in_program();

     return NIL;
}

/*
------------------------------------------------------------------------------
	FUNCTION
	<assoc>:
------------------------------------------------------------------------------
*/

CELL *assoc(CELL *item, CELL *alist)
{
     for ( ; (!equal(item, (car(car(alist)))) && (!Lisp_Null(alist)));
	      alist = cdr(alist))
	  ;
     return car(alist);
}
	      
/*
------------------------------------------------------------------------------
	PROCEDURE
	<s_print>: pretty print S-expression
------------------------------------------------------------------------------
*/

CELL *s_print(FILE *fp, CELL *cell)
{
     _s_print_(fp, cell);
     fputc('\n', fp);
}

CELL *_s_print_(FILE *fp, CELL *cell)
{
     if (Lisp_Null(cell))
	  fprintf(fp, "%s", NILSYMBOL);
     else {
	  switch (_Tag(cell)) {
	  case CONS:
	       fprintf(fp, "%c", BPARENTHESIS);
	       _s_print_(fp, _Car(cell));
	       _s_print_cdr(fp, _Cdr(cell));
	       fprintf(fp, "%c", EPARENTHESIS);
	       break;
	  case ATOM:
	       fprintf(fp, "%s", _Atom(cell));
	       break;
	  default:
	      fprintf(stderr, "Illegal cell(in s_print)\n");
	      my_exit(OtherError);
	      /* error(OtherError, "Illegal cell(in s_print)", EOA); */
	  }
     }

     return cell;
}

CELL *_s_print_cdr(FILE *fp, CELL *cell)
{
     if (!Lisp_Null(cell)) {
	  if (Consp(cell)) {
	       fprintf(fp, " ");
	       _s_print_(fp, _Car(cell));
	       _s_print_cdr(fp, _Cdr(cell));
	  } else {
	       fputc(' ', fp);
	       _s_print_(fp, cell);
	  }
     }

     return cell;
}

void *my_alloc(int n)
{
     void *p;

     if ((p = (void *)malloc(n)) == NULL) {
	 fprintf(stderr, "Not enough memory. Can't allocate.\n");
	 my_exit(AllocateError);
	 /* error(AllocateError, "Not enough memory. Can't allocate.", EOA); */
     }

     return p;
}

/*
------------------------------------------------------------------------------
	PROCEDURE			by yamaji
	<lisp_alloc>: あらかじめ一定領域を確保しておいて malloc を行う
------------------------------------------------------------------------------
*/

void *lisp_alloc(int n)
{
     CELLTABLE	*tbl;
     CELL *p;

     if (n % sizeof(CELL)) n = n/sizeof(CELL)+1; else n /= sizeof(CELL);
     if (CellTbl == NULL || CellTbl != NULL && CellTbl->n+n > CellTbl->max) {
	 /* 新たに一定領域を確保 */
	 if (CellTbl != NULL && CellTbl->next != NULL) {
	     CellTbl = CellTbl->next;
	     CellTbl->n = 0;
	 } else {
	     tbl = (CELLTABLE *)my_alloc(sizeof(CELLTABLE));
	     tbl->cell = (CELL *)my_alloc(sizeof(CELL)*BLOCKSIZE);
	     tbl->pre  = CellTbl;
	     tbl->next = NULL;
	     tbl->max  = BLOCKSIZE;
	     tbl->n    = 0;
	     if (CellTbl != NULL) CellTbl->next = tbl;
	     CellTbl = tbl;
	 }
     }
     p = CellTbl->cell + CellTbl->n;
     CellTbl->n += n;
     if (CellTbl->n > CellTbl->max) error_in_lisp();

     return((void *)p);
}

/*
------------------------------------------------------------------------------
	PROCEDURE			by yamaji
	<lisp_alloc_push>: 現在のメモリアロケート状態を記憶する
------------------------------------------------------------------------------
*/

void lisp_alloc_push(void)
{
    CellTbl_save = *CellTbl;
}

/*
------------------------------------------------------------------------------
	PROCEDURE			by yamaji
	<lisp_alloc_pop>: 記憶したメモリアロケート状態に戻す
------------------------------------------------------------------------------
*/

void lisp_alloc_pop(void)
{
    CellTbl->cell = CellTbl_save.cell;
    CellTbl->n    = CellTbl_save.n;
}


int ifnextchar_string(char **chp, int i)
{
     int c;

     do {
	 c = (int)*(chp)[0];
	 ++*(chp);
	  if (c == '\n') LineNo++;
     } while (c == ' ' || c == '\t' || c == '\n' || c == '\r');

     if (c == '\0') return EOF;

     if (i == c) {
	 return TRUE;
     } else {
	 --*(chp);
	  return FALSE;
     }
}

CELL *s_read_car_string(char **chp)
{
     CELL	*cell;
     int	n;

     if ((n = ifnextchar_string(chp, (int)EPARENTHESIS)) == TRUE) {
	 cell = (CELL *)NIL;
	 return cell;
     } else if (n == FALSE) {
	  cell = new_cell();
	  _Car(cell) = s_read_from_string(chp);
	  _Cdr(cell) = s_read_cdr_string(chp);
	  return cell;
     }

     if (n == EOF) error_in_lisp();
     else          error_in_program();

     return NIL;
}

CELL *s_read_cdr_string(char **chp)
{
     CELL	*cell;
     int	n;

     if ((n = ifnextchar_string(chp, (int)EPARENTHESIS)) == TRUE) {
	  cell = (CELL *)NIL;
	  return cell;
     } else if (n == FALSE) {
	  cell = s_read_car_string(chp);
	  return cell;
     }

     if (n == EOF) error_in_lisp();
     else          error_in_program();

     return NIL;
}

CELL *s_read_atom_string (char **chp)
{
     CELL *cell;
     U_CHAR *c;
     int n;

     if (((n = myscanf_string(chp, Buffer)) == 0) || (n == EOF)) {
	  error_in_lisp();
     }

     if (!strcmp(Buffer, NILSYMBOL)) {
	  cell = NIL;
     } else {
	  cell = new_cell();
	  _Tag(cell) = ATOM;
	  c = (U_CHAR *)lisp_alloc(sizeof(U_CHAR) * (strlen(Buffer)+1));
	  strcpy(c, Buffer);
	  _Atom(cell) = c;
     }

     return cell;
}

CELL *s_read_from_string (char **sexp)
{
     int n;

     if ((n = ifnextchar_string(sexp, (int)BPARENTHESIS)) == TRUE) {
	  return s_read_car_string(sexp);
     } else if (n == FALSE) {
	 return s_read_atom_string(sexp);
     }

     if (n == EOF) error_in_lisp();
     else	   error_in_program();

     return NIL;
}
