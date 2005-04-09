/*------------------------------------------------------------------------*/
/**
 * @file	newt.l
 * @brief   ������
 *
 * @author  M.Nukui
 * @date	2003-11-07
 *
 * Copyright (C) 2003-2004 M.Nukui All rights reserved.
 */

/*
%option interactive
*/

%option noyywrap

%{

/* �w�b�_�t�@�C�� */
#include <string.h>

#include "NewtErrs.h"
#include "NewtObj.h"
#include "NewtEnv.h"
#include "NewtParser.h"
#include "NewtPrint.h"
#include "NewtIO.h"

#include "lookup_words.h"
#include "yacc.h"
#include "y.tab.h"


/* �֐��v���g�^�C�v */
static int			lex_update_tokenpos(int op);
static void			lex_newline(void);

static char *		lex_truncstr(char *s);
static char *		lex_escapestr(char *s);
static char			lex_escapechar(char c);
static int			lex_htoi(char *s, int len);
static uint32_t		lex_getop(char *s);
static int			lex_op(char *s, int op);
static int			lex_reserveword(int tokn, char *s);

static int			lex_makesymbol(char *s, bool trunc);
static int			lex_makestring(char *s, bool trunc);
static int			lex_makeregex(char *s, bool trunc);
static int			lex_makechar(int c);
static int			lex_makeinteger(int n);
static int			lex_makereal(double n);

static int			lex_makemagicpointer(int n);
static int			lex_makenamedmp(char *s, bool trunc);

static void			lex_debug(int type);


/* �}�N�� */
#undef YY_INPUT
#define YY_INPUT(b, r, ms) (r=nps_yyinput(yyin, b, ms))

#define WORN_NOS2(msg)		if (NEWT_MODE_NOS2) NPSErrorStr('W', msg);

%}

%x COMMENT
%x SHELL
%s BINARY
%x STRING
%x REGEX

ALPHA					[A-Za-z]
DIGIT					[0-9]
HEX-DIGIT				({DIGIT}|[A-Fa-f])
REAL					{DIGIT}+"."{DIGIT}*([eE]-?{DIGIT}+)?

NEWLINE					("\r\n"|"\r"|"\n")
SPACE					[ \t]
STRING-CHARACTER		[\x20-\x21\x23-\x5b\x5d-\x7f]
SYMBOL-CHARACTER		[\x20-\x5b\x5d-\x7b\x7d-\x7f]
REGEX-CHARACTER			({STRING-CHARACTER}|"\"")
NON-ESCAPE-CHARACTER	[\x20-\x5b\x5d-\x7f]
ESCAPE-CHAR				("\""|[\\nrt/])
ESCAPE-SEQUENCE			(("\\"{ESCAPE-CHAR})|("\\u"({HEX-DIGIT}{4})*"\\u"))
TRUNCATED-ESCAPE		"\\u"({HEX-DIGIT}{4})*

CHARACTER-SEQUENCE		({STRING-CHARACTER}|{ESCAPE-SEQUENCE})*{TRUNCATED-ESCAPE}?
SYMBOL					({ALPHA}|"_")({ALPHA}|{DIGIT}|"_")*
SYMBOL-SEQUENCE			("\\"[|\\]|{SYMBOL-CHARACTER})*
REGEX-SEQUENCE			({REGEX-CHARACTER}|{ESCAPE-SEQUENCE})*{TRUNCATED-ESCAPE}?

%%

%{
    if (nps_env.first_time)
    {   //����N����
        nps_env.first_time = false;
        BEGIN SHELL;
    }
%}


"//".*$

"/*"							BEGIN COMMENT;
<COMMENT>"*/"					BEGIN INITIAL;
<COMMENT>{NEWLINE}				lex_newline();
<COMMENT>(.|{SPACE})			;

"<#"							{
									BEGIN BINARY;
									return lex_update_tokenpos(kBINBG);
								}

<BINARY>{NEWLINE}				lex_newline();
<BINARY>">"						{
									BEGIN INITIAL;
									return lex_update_tokenpos(kBINED);
								}

<STRING>{NEWLINE}				{
									nps_env.lineno++;
									yymore();
								}

<STRING>{CHARACTER-SEQUENCE}	yymore();
<STRING>"\""					{
									BEGIN INITIAL;
									return lex_makestring(yytext, true);
								}

<REGEX>{ALPHA}+					{ return lex_makestring(yytext, false); }
<REGEX>.						{
									unput(*yytext);
									BEGIN INITIAL;
								}

{NEWLINE}						lex_newline();
{SPACE}+						lex_update_tokenpos(0);

__FILE__						{ return lex_makestring((char *)(nps_env.fname?nps_env.fname:"-"), false); }
__LINE__						{ return lex_makeinteger(nps_env.lineno); }

[+-]							{ return lex_op(yytext, kADDOP); }
[*/]							{ return lex_op(yytext, kMULOP); }
("&"|"&&")						{ return lex_op(yytext, kSTROP); }
("<<"|">>")						{ return lex_op(yytext, kSFTOP); }
([<>]"="?|"="|"<>"|"==")		{ return lex_op(yytext, kRELOP); }
"..."							{ return lex_update_tokenpos(k3READER); }

":="							{ return lex_update_tokenpos(kASNOP); }
":?"							{ return lex_update_tokenpos(kSNDOP); }

"\""{CHARACTER-SEQUENCE}"\""	{ return lex_makestring(yytext, true); }

"\""							{
									BEGIN STRING;
									yymore();
								}

{SYMBOL}						{ return lex_makesymbol(yytext, false); }
"|"{SYMBOL-SEQUENCE}"|"			{ return lex_makesymbol(yytext, true); }

"/"{REGEX-SEQUENCE}"/"			{
									BEGIN REGEX;
									return lex_makeregex(yytext, true);
								}

"$\\"{ESCAPE-CHAR}				{ return lex_makechar(lex_escapechar(yytext[2])); }
"$\\"{HEX-DIGIT}{2}				{ return lex_makechar(lex_htoi(yytext + 2, -1)); }
"$\\u"{HEX-DIGIT}{4}			{ return lex_makechar(lex_htoi(yytext + 3, -1)); }
"$"{NON-ESCAPE-CHARACTER}		{ return lex_makechar(yytext[1]); }

"@"{DIGIT}+						{ return lex_makemagicpointer(atoi(yytext + 1)); }
"@"{SYMBOL}						{ return lex_makenamedmp(yytext + 1, false); }
"@""|"{SYMBOL-SEQUENCE}"|"		{ return lex_makenamedmp(yytext + 1, true); }

{DIGIT}+						{ return lex_makeinteger(atoi(yytext)); }
"0x"{HEX-DIGIT}+				{ return lex_makeinteger(lex_htoi(yytext + 2, -1)); }

{REAL}							{ return lex_makereal(atof(yytext)); }

.								{ return lex_update_tokenpos(yytext[0]); }

<SHELL>^"#".*$					{ BEGIN INITIAL; }
<SHELL>{NEWLINE}				lex_newline();
<SHELL>.						{
									unput(*yytext);
									BEGIN INITIAL;
								}

%%


/// �ꕔ�� lex �� YY_FLUSH_BUFFER �� undef ����Ă��܂����ɑΉ�
#ifndef YY_FLUSH_BUFFER
	#define YY_FLUSH_BUFFER yy_flush_buffer(YY_CURRENT_BUFFER )
#endif


/// �\���
static keyword_t	reserved_words[] = {
		// �A���t�@�x�b�g���Ƀ\�[�g���Ă�������
		{"AND",			kANDOP},		// �\���
        {"BEGIN",		kBEGIN},		// �\���
        {"BREAK",		kBREAK},		// �\���
        {"BY",			kBY},			// �\���
        {"CALL",		kCALL},			// �\���
//		{"COLLECT",		kCOLLECT},
        {"CONSTANT",	kCONSTANT},		// �\���
//		{"DEEPLY",		kDEEPLY},
        {"DIV",			kMULOP},		// �\���
        {"DO",			kDO},			// �\���
        {"ELSE",		kELSE},			// �\���
        {"END",			kEND},			// �\���
        {"EXISTS",		kEXISTS},		// �\���
        {"FOR",			kFOR},			// �\���
        {"FOREACH",		kFOREACH},		// �\���
        {"FUNC",		kFUNC},			// �\���
        {"GLOBAL",		kGLOBAL},		// �\���
        {"IF",			kIF},			// �\���
        {"IN",			kIN},			// �\���
        {"INHERITED",	kINHERITED},	// �\���
        {"LOCAL",		kLOCAL},		// �\���
        {"LOOP",		kLOOP},			// �\���
        {"MOD",			kMULOP},		// �\���
        {"NATIVE",		kNATIVE},		// �\���
        {"NIL",			kNIL},
        {"NOT",			kNOTOP},		// �\���
        {"ONEXCEPTION",	kONEXCEPTION},	// �\���
        {"OR",			kANDOP},		// �\���
        {"REPEAT",		kREPEAT},		// �\���
        {"RETURN",		kRETURN},		// �\���
        {"SELF",		kSELF},			// �\���
        {"THEN",		kTHEN},			// �\���
        {"TO",			kTO},			// �\���
        {"TRUE",		kTRUE},
        {"TRY",			kTRY},			// �\���
        {"UNTIL",		kUNTIL},		// �\���
        {"WHILE",		kWHILE},		// �\���
        {"WITH",		kWITH},			// �\���
    };

/// �I�y���[�^
static keyword_t	operator_words[] = {
		// �A���t�@�x�b�g���Ƀ\�[�g���Ă�������
        {"&&",			kNPS_CONCAT2},
        {"<<",			kNPS_SHIFT_LEFT},
        {"<=",			kNPS_LESS_EQUAL},
        {"<>",			kNPS_NOT_EQUAL},
        {"==",			kNPS_OBJECT_EQUAL},
        {">=",			kNPS_GREATER_EQUAL},
        {">>",			kNPS_SHIFT_RIGHT},
	};


/*------------------------------------------------------------------------*/
/** �g�[�N���̈ʒu���X�V
 *
 * @param op		[in] �I�y���[�^
 *
 * @return			�I�y���[�^�����̂܂ܕԂ�
 */

int lex_update_tokenpos(int op)
{
	strncat(nps_env.linebuf, yytext, sizeof(nps_env.linebuf));

	nps_env.tokenpos += yyleng;
	nps_env.yyleng = yyleng;
	return op;
}


/*------------------------------------------------------------------------*/
/** �V�����s�̏�����
 *
 * @return			�Ȃ�
 *
 * @note			�G���[�ӏ���K�؂ɕ\�����邽�߂ɓ��͍s��ێ�����
 */

void lex_newline(void)
{
	uint32_t	n = 1;

	if (yytext[0] == '\r' && yytext[1] == '\n')
		n++;

	nps_env.linebuf[0] = '\0';
	nps_env.tokenpos = 0;
	nps_env.yyleng = 0;
	nps_env.lineno++;
	yyless(n);
}


/*------------------------------------------------------------------------*/
/** ������̑O��P������؂�l�߂�
 *
 * @param s			[in] ������
 *
 * @return			�؂�l�߂���ꂽ������
 */

char * lex_truncstr(char *s)
{
    s[strlen(s) - 1] = '\0';

    return s + 1;
}


/*------------------------------------------------------------------------*/
/** �G�X�P�[�v���ꂽ���������������
 *
 * @param s			[in] �G�X�P�[�v���ꂽ������
 *
 * @return			������
 */

char * lex_escapestr(char *s)
{
    int		uni = 0;
    char *	src;
    char *	dst;

    dst = src = s;

    while (*src)
    {
        if (*src =='\\')
        {
            src++;

            if (*src == 'u')
            {
                uni = ! uni;
            }
            else
            {
              	*dst = lex_escapechar(*src);
                dst++;
            }

            src++;
        }
        else if (uni)
        {
/*
            *dst = lex_htoi(src, 4);
            src += 4;
            dst++;
*/
            *dst = lex_htoi(src, 2);
            src += 2;
            dst++;

            *dst = lex_htoi(src, 2);
            src += 2;
            dst++;
        }
        else
        {
            if (dst != src)
                *dst = *src;

            dst++;
            src++;
        }
    }

    *dst = '\0';

    return s;
}


/*------------------------------------------------------------------------*/
/** �G�X�P�[�v��������������
 *
 * @param c			[in] �G�X�P�[�v����
 *
 * @return			����
 */

char lex_escapechar(char c)
{
    switch (c)
    {
        case 'n':
            c = '\n';
            break;

        case 'r':
            c = '\r';
            break;

        case 't':
            c = '\t';
            break;
    }

    return c;
}


/*------------------------------------------------------------------------*/
/** 16�i��������𐮐��ɕϊ�
 *
 * @param s			[in] 16�i��������
 * @param len		[in] 16�i��������̒���
 *
 * @return			����
 */

int lex_htoi(char *s, int len)
{
    int	n = 0;

    if (len < 0)
        len = strlen(s) + 1 + len;

    while (0 < len)
    {
        n *= 16;

        if ('A' <= *s && *s <= 'F')
            n += *s - 'A' + 10;
        else if ('a' <= *s && *s <= 'f')
            n += *s - 'a' + 10;
        else
            n += *s - '0';

        s++;
        len--;
    }

    return n;
}


/*------------------------------------------------------------------------*/
/** �I�y���[�^�����񂩂�I�y���[�^ID�����߂�
 *
 * @param s			[in] �I�y���[�^������
 *
 * @return			�I�y���[�^ID
 */

uint32_t lex_getop(char *s)
{
    uint32_t	op;
    int	len;

	len = strlen(s);

    if (len == 1)
    {
        op = s[0];
    }
    else
    {
        int	wlen;

        wlen = sizeof(operator_words) / sizeof(keyword_t);
        op = lookup_words(operator_words, wlen, s);
    }

    return op;
}


/*------------------------------------------------------------------------*/
/** �I�y���[�^�g�[�N���̍쐬
 *
 * @param s			[in] �I�y���[�^������
 *
 * @return			�g�[�N��ID
 */

int lex_op(char *s, int op)
{
    yylval.op = lex_getop(yytext);
	return lex_update_tokenpos(op);
}


/*------------------------------------------------------------------------*/
/** �\���̃g�[�N�����쐬
 *
 * @param tokn		[in] �g�[�N��ID
 * @param s			[in] �I�y���[�^������
 *
 * @return			�g�[�N��ID
 */

int lex_reserveword(int tokn, char *s)
{
    switch (tokn)
    {
        case kMULOP:
            if (strcasecmp(s, "div") == 0)
                yylval.op = kNPS_DIV;
            else if (strcasecmp(s, "mod") == 0)
                yylval.op = kNPS_MOD;
            break;

        case kANDOP:
            if (strcasecmp(s, "and") == 0)
                yylval.op = kNPS_AND;
            else if (strcasecmp(s, "or") == 0)
                yylval.op = kNPS_OR;
            break;

        case kNOTOP:
            yylval.op = kNPS_NOT;
            break;
    }

    return tokn;
}


/*------------------------------------------------------------------------*/
/** �V���{���g�[�N���̍쐬
 *
 * @param s			[in] ������
 * @param trunc		[in] �O��̐؂�l��
 *
 * @return			�g�[�N��ID
 */

int lex_makesymbol(char *s, bool trunc)
{
    if (trunc)
    {
        s = lex_escapestr(lex_truncstr(s));
    }
    else
    {
        int	tokn;
        int	wlen;

        wlen = sizeof(reserved_words) / sizeof(keyword_t);
        tokn = lookup_words(reserved_words, wlen, s);

        if (tokn != -1)
            return lex_update_tokenpos(lex_reserveword(tokn, s));
    }

    yylval.obj = NewtMakeSymbol(s);
    lex_debug(kSYMBOL);

	return lex_update_tokenpos(kSYMBOL);
}


/*------------------------------------------------------------------------*/
/** ������g�[�N���̍쐬
 *
 * @param s			[in] ������
 * @param trunc		[in] �O��̐؂�l��
 *
 * @return			�g�[�N��ID
 */

int lex_makestring(char *s, bool trunc)
{
    if (trunc)
        s = lex_escapestr(lex_truncstr(s));

    yylval.obj = NewtMakeString(s, true);
    lex_debug(kSTRING);

	return lex_update_tokenpos(kSTRING);
}


/*------------------------------------------------------------------------*/
/** ���K�\���g�[�N���̍쐬
 *
 * @param s			[in] ������
 * @param trunc		[in] �O��̐؂�l��
 *
 * @return			�g�[�N��ID
 */

int lex_makeregex(char *s, bool trunc)
{
    if (trunc)
        s = lex_escapestr(lex_truncstr(s));

    yylval.obj = NewtMakeString(s, true);
    lex_debug(kREGEX);

	return lex_update_tokenpos(kREGEX);
}


/*------------------------------------------------------------------------*/
/** �����g�[�N���̍쐬
 *
 * @param c			[in] ����
 *
 * @return			�g�[�N��ID
 */

int lex_makechar(int c)
{
    yylval.obj = NewtMakeCharacter(c);
    lex_debug(kCHARACTER);

	return lex_update_tokenpos(kCHARACTER);
}


/*------------------------------------------------------------------------*/
/** �����g�[�N���̍쐬
 *
 * @param n			[in] ����
 *
 * @return			�g�[�N��ID
 */

int lex_makeinteger(int n)
{
    yylval.obj = NewtMakeInteger(n);
    lex_debug(kINTEGER);

	return lex_update_tokenpos(kINTEGER);
}


/*------------------------------------------------------------------------*/
/** ���������_�g�[�N���̍쐬
 *
 * @param n			[in] ���������_
 *
 * @return			�g�[�N��ID
 */

int lex_makereal(double n)
{
    yylval.obj = NewtMakeReal(n);
    lex_debug(kREAL);

	return lex_update_tokenpos(kREAL);
}


#ifdef __NAMED_MAGIC_POINTER__

/*------------------------------------------------------------------------*/
/** �}�W�b�N�|�C���^�g�[�N���̍쐬
 *
 * @param n			[in] �}�W�b�N�|�C���^�ԍ�
 *
 * @return			�g�[�N��ID
 */

int lex_makemagicpointer(int n)
{
	return lex_update_tokenpos(kERROR);
}


/*------------------------------------------------------------------------*/
/** ���O�t�}�W�b�N�|�C���^�̍쐬
 *
 * @param s			[in] ������
 * @param trunc		[in] �O��̐؂�l��
 *
 * @return			�g�[�N��ID
 */

int lex_makenamedmp(char *s, bool trunc)
{
	int		pos;

    if (trunc)
    {
        s = lex_escapestr(lex_truncstr(s));
    }

    yylval.obj = NewtMakeNamedMP(s);
    lex_debug(kMAGICPOINTER);

	pos = lex_update_tokenpos(kMAGICPOINTER);

	// NOS2 ��݊�
	WORN_NOS2("Named Magic Pinter");

	return pos;
}

#else

/*------------------------------------------------------------------------*/
/** �}�W�b�N�|�C���^�g�[�N���̍쐬
 *
 * @param n			[in] �}�W�b�N�|�C���^�ԍ�
 *
 * @return			�g�[�N��ID
 */

int lex_makemagicpointer(int n)
{
	if (0x03ff < n)
	{	// ���l���͈͊O
		return lex_update_tokenpos(kERROR);
	}

	yylval.obj = NewtMakeMagicPointer(0, n);
    lex_debug(kMAGICPOINTER);

	return lex_update_tokenpos(kMAGICPOINTER);
}


/*------------------------------------------------------------------------*/
/** ���O�t�}�W�b�N�|�C���^�̍쐬
 *
 * @param s			[in] ������
 * @param trunc		[in] �O��̐؂�l��
 *
 * @return			�g�[�N��ID
 */

int lex_makenamedmp(char *s, bool trunc)
{
	return lex_update_tokenpos(kERROR);
}

#endif


#pragma mark -
/*------------------------------------------------------------------------*/
/** �f�o�b�O�\��
 *
 * @param type		[in] �g�[�N��ID
 *
 * @return			�Ȃ�
 */

void lex_debug(int type)
{
    char *	name = "unknown";

    if (! NEWT_DUMPLEX)
        return;

    switch (type)
    {
        case kSYMBOL:
            name = "symbol";
            break;

        case kSTRING:
            name = "string";
            break;

        case kINTEGER:
            name = "integer";
            break;

        case kREAL:
            name = "real";
            break;

		case kMAGICPOINTER:
            name = "magic pointer";
			break;
    }

    NewtFprintf(stderr, "  %s\t==> ", name);
    NewtPrintObject(stderr, yylval.obj);
}


#pragma mark -
//--------------------------------------------------------------------------
/** �����͂̂��߂̏�����
 *
 * @return			�Ȃ�
 */

void nps_yyinit(void)
{
	static bool inited = false;

	if (! inited)
	{   //�P��e�[�u���̃\�[�g
		lookup_sorttable(reserved_words, sizeof(reserved_words) / sizeof(keyword_t));
		lookup_sorttable(operator_words, sizeof(operator_words) / sizeof(keyword_t));

		inited = true;
	}
}


//--------------------------------------------------------------------------
/** �����͂̌�n��
 *
 * @return			�Ȃ�
 */

int nps_yycleanup(void)
{
	BEGIN INITIAL;
	YY_FLUSH_BUFFER;
	yyterminate();
}