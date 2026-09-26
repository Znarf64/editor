package fontconfig

// Odin bindings for fontconfig (https://www.freedesktop.org/wiki/Software/fontconfig/)
// Translated from fontconfig/fontconfig.h
//
// Link against the system fontconfig library, e.g. on Linux:
//   -lfontconfig
// or via pkg-config: `pkg-config --libs fontconfig`

import "core:c"

when ODIN_OS == .Windows {
	foreign import fc "system:fontconfig.lib"
} else {
	foreign import fc "system:fontconfig"
}

// ---------------------------------------------------------------------------
// Basic scalar types
// ---------------------------------------------------------------------------

Char8  :: u8
Char16 :: u16
Char32 :: rune
Bool   :: b32

Object :: c.int

// ---------------------------------------------------------------------------
// Version
// ---------------------------------------------------------------------------

MAJOR    :: 2
MINOR    :: 18
REVISION :: 3

VERSION :: (MAJOR * 10000) + (MINOR * 100) + (REVISION)

CACHE_VERSION_NUMBER      :: 12
CACHE_SNAP_VERSION_NUMBER :: 0
NEXT_CACHE_VERSION_NUMBER :: 0
CACHE_MIN_COMPAT_VERSION  :: 9

// FC_NEXT_CACHE_VERSION_NUMBER is 0, so this mirrors the non-snapshot branch
// of the C header's #if.
CACHE_VERSION :: "12"

// ---------------------------------------------------------------------------
// Pattern object name constants
// ---------------------------------------------------------------------------

FAMILY               :: cstring("family")         /* String */
STYLE                :: cstring("style")          /* String */
SLANT                :: cstring("slant")          /* Int */
WEIGHT               :: cstring("weight")         /* Int */
SIZE                 :: cstring("size")           /* Range (double) */
ASPECT               :: cstring("aspect")         /* Double */
PIXEL_SIZE           :: cstring("pixelsize")      /* Double */
SPACING              :: cstring("spacing")        /* Int */
FOUNDRY              :: cstring("foundry")        /* String */
ANTIALIAS            :: cstring("antialias")      /* Bool (depends) */
HINTING              :: cstring("hinting")        /* Bool (true) */
HINT_STYLE           :: cstring("hintstyle")      /* Int */
VERTICAL_LAYOUT      :: cstring("verticallayout") /* Bool (false) */
AUTOHINT             :: cstring("autohint")       /* Bool (false) */
/* FC_GLOBAL_ADVANCE is deprecated. this is simply ignored on freetype 2.4.5 or later */
GLOBAL_ADVANCE       :: cstring("globaladvance")  /* Bool (true) */
WIDTH                :: cstring("width")          /* Int */
FILE                 :: cstring("file")           /* String */
INDEX                :: cstring("index")          /* Int */
FT_FACE              :: cstring("ftface")         /* FT_Face */
RASTERIZER           :: cstring("rasterizer")     /* String (deprecated) */
OUTLINE              :: cstring("outline")        /* Bool */
SCALABLE             :: cstring("scalable")       /* Bool */
COLOR                :: cstring("color")          /* Bool */
VARIABLE             :: cstring("variable")       /* Bool */
SCALE                :: cstring("scale")          /* double (deprecated) */
SYMBOL               :: cstring("symbol")         /* Bool */
DPI                  :: cstring("dpi")            /* double */
RGBA                 :: cstring("rgba")           /* Int */
MINSPACE             :: cstring("minspace")       /* Bool use minimum line spacing */
SOURCE               :: cstring("source")         /* String (deprecated) */
CHARSET              :: cstring("charset")        /* CharSet */
LANG                 :: cstring("lang")           /* LangSet Set of RFC 3066 langs */
FONTVERSION          :: cstring("fontversion")    /* Int from 'head' table */
FULLNAME             :: cstring("fullname")       /* String */
FAMILYLANG           :: cstring("familylang")     /* String RFC 3066 langs */
STYLELANG            :: cstring("stylelang")      /* String RFC 3066 langs */
FULLNAMELANG         :: cstring("fullnamelang")   /* String RFC 3066 langs */
CAPABILITY           :: cstring("capability")     /* String */
FONTFORMAT           :: cstring("fontformat")     /* String */
EMBOLDEN             :: cstring("embolden")       /* Bool - true if emboldening needed*/
EMBEDDED_BITMAP      :: cstring("embeddedbitmap") /* Bool - true to enable embedded bitmaps */
DECORATIVE           :: cstring("decorative")     /* Bool - true if style is a decorative variant */
LCD_FILTER           :: cstring("lcdfilter")      /* Int */
FONT_FEATURES        :: cstring("fontfeatures")   /* String */
FONT_VARIATIONS      :: cstring("fontvariations") /* String */
NAMELANG             :: cstring("namelang")       /* String RFC 3866 langs */
PRGNAME              :: cstring("prgname")        /* String */
HASH                 :: cstring("hash")           /* String (deprecated) */
POSTSCRIPT_NAME      :: cstring("postscriptname") /* String */
FONT_HAS_HINT        :: cstring("fonthashint")    /* Bool - true if font has hinting */
ORDER                :: cstring("order")          /* Integer */
DESKTOP_NAME         :: cstring("desktop")        /* String */
NAMED_INSTANCE       :: cstring("namedinstance")  /* Bool - true if font is named instance */
FONT_WRAPPER         :: cstring("fontwrapper")    /* String */
GENERIC_FAMILY       :: cstring("genericfamily")  /* Integer */

// NOTE: Odin constants can't use `+` to concatenate strings, so these are
// pre-computed from FC_CACHE_VERSION ("12") rather than built with it.
CACHE_SUFFIX    :: ".cache-12"
DIR_CACHE_FILE  :: "fonts.cache-12"
USER_CACHE_FILE :: ".fonts.cache-12"

// Adjust outline rasterizer
CHARWIDTH   :: cstring("charwidth")  /* Int */
CHAR_WIDTH  :: CHARWIDTH
CHAR_HEIGHT :: cstring("charheight") /* Int */
MATRIX      :: cstring("matrix")     /* Matrix */

// ---------------------------------------------------------------------------
// Weight / slant / width / spacing / rgba / hint / lcd / family constants
// ---------------------------------------------------------------------------

WEIGHT_THIN       :: 0
WEIGHT_EXTRALIGHT :: 40
WEIGHT_ULTRALIGHT :: WEIGHT_EXTRALIGHT
WEIGHT_LIGHT      :: 50
WEIGHT_DEMILIGHT  :: 55
WEIGHT_SEMILIGHT  :: WEIGHT_DEMILIGHT
WEIGHT_BOOK       :: 75
WEIGHT_REGULAR    :: 80
WEIGHT_NORMAL     :: WEIGHT_REGULAR
WEIGHT_MEDIUM     :: 100
WEIGHT_DEMIBOLD   :: 180
WEIGHT_SEMIBOLD   :: WEIGHT_DEMIBOLD
WEIGHT_BOLD       :: 200
WEIGHT_EXTRABOLD  :: 205
WEIGHT_ULTRABOLD  :: WEIGHT_EXTRABOLD
WEIGHT_BLACK      :: 210
WEIGHT_HEAVY      :: WEIGHT_BLACK
WEIGHT_EXTRABLACK :: 215
WEIGHT_ULTRABLACK :: WEIGHT_EXTRABLACK

SLANT_ROMAN   :: 0
SLANT_ITALIC  :: 100
SLANT_OBLIQUE :: 110

WIDTH_ULTRACONDENSED :: 50
WIDTH_EXTRACONDENSED :: 63
WIDTH_CONDENSED      :: 75
WIDTH_SEMICONDENSED  :: 87
WIDTH_NORMAL         :: 100
WIDTH_SEMIEXPANDED   :: 113
WIDTH_EXPANDED       :: 125
WIDTH_EXTRAEXPANDED  :: 150
WIDTH_ULTRAEXPANDED  :: 200

SPACING_PROPORTIONAL :: 0
SPACING_DUAL         :: 90
SPACING_MONO         :: 100
SPACING_CHARCELL     :: 110
PROPORTIONAL         :: SPACING_PROPORTIONAL
DUAL                 :: SPACING_DUAL
MONO                 :: SPACING_MONO
CHARCELL             :: SPACING_CHARCELL

// sub-pixel order
RGBA_UNKNOWN :: 0
RGBA_RGB     :: 1
RGBA_BGR     :: 2
RGBA_VRGB    :: 3
RGBA_VBGR    :: 4
RGBA_NONE    :: 5

// hinting style
HINT_NONE   :: 0
HINT_SLIGHT :: 1
HINT_MEDIUM :: 2
HINT_FULL   :: 3

// LCD filter
LCD_NONE    :: 0
LCD_DEFAULT :: 1
LCD_LIGHT   :: 2
LCD_LEGACY  :: 3

// Generic family
FAMILY_UNKNOWN    :: 0
FAMILY_SERIF      :: 1
FAMILY_SANS       :: 2
FAMILY_MONO       :: 3
FAMILY_CURSIVE    :: 4
FAMILY_FANTASY    :: 5
FAMILY_SYSTEM_UI  :: 6
FAMILY_UI_SERIF   :: 7
FAMILY_UI_SANS    :: 8
FAMILY_UI_MONO    :: 9
FAMILY_UI_ROUNDED :: 10
FAMILY_EMOJI      :: 11
FAMILY_MATH       :: 12
FAMILY_FANGSONG   :: 13

// Warnings
WARN_INVALID_ATTR :: (1 << 0)

CHARSET_MAP_SIZE :: 256 / 32
CHARSET_DONE     :: max(Char32)

UTF8_MAX_LEN :: 6

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

Type :: enum c.int {
	Unknown = -1,
	Void,
	Integer,
	Double,
	String,
	Bool,
	Matrix,
	CharSet,
	FTFace,
	LangSet,
	Range,
}

Result :: enum c.int {
	Match,
	NoMatch,
	TypeMismatch,
	NoId,
	OutOfMemory,
}

ValueBinding :: enum c.int {
	Weak,
	Strong,
	Same,
	End = max(c.int),
}

MatchKind :: enum c.int {
	Pattern = 0,
	Font,
	Scan,
	KindEnd,
	KindBegin = Pattern,
}

LangResult :: enum c.int {
	Equal              = 0,
	DifferentCountry   = 1,
	DifferentTerritory = 1,
	DifferentLang      = 2,
}

SetName :: enum c.int {
	System      = 0,
	Application = 1,
}

Endian :: enum c.int {
	Big,
	Little,
}

// ---------------------------------------------------------------------------
// Structs (opaque and transparent)
// ---------------------------------------------------------------------------

Matrix :: struct {
	xx, xy, yx, yy: c.double,
}

MatrixInit :: proc(m: ^Matrix) {
	m.xx = 1
	m.yy = 1
	m.xy = 0
	m.yx = 0
}

// Opaque types - only ever referenced via pointers.
CharSet   :: struct {}
Pattern   :: struct {}
LangSet   :: struct {}
Range     :: struct {}
Config    :: struct {}
FileCache :: struct {} // FcGlobalCache
Blanks    :: struct {}
StrList   :: struct {}
StrSet    :: struct {}
Cache     :: struct {}
Atomic    :: struct {}

PatternIter :: struct {
	dummy1: rawptr,
	dummy2: rawptr,
}

ConfigFileInfoIter :: struct {
	dummy1: rawptr,
	dummy2: rawptr,
	dummy3: rawptr,
}

ObjectType :: struct {
	object: cstring,
	type:   Type,
}

Constant :: struct {
	name:   cstring,
	object: cstring,
	value:  c.int,
}

Value :: struct {
	type: Type,
	u:    struct #raw_union {
		s:   cstring,
		i:   c.int,
		b:   Bool,
		d:   c.double,
		m:   ^Matrix,
		c:   ^CharSet,
		f:   rawptr,
		l:   ^LangSet,
		rng: ^Range,
	},
}

FontSet :: struct {
	nfont: c.int,
	sfont: c.int,
	fonts: [^]^Pattern,
}

ObjectSet :: struct {
	nobject: c.int, // deprecated
	sobject: c.int,
	objects: [^]cstring, // deprecated
	nobjIds: c.int,
	objIds:  [^]Object,
}

DestroyFunc       :: #type proc "c" (data: rawptr)
FilterFontSetFunc :: #type proc "c" (font: ^Pattern, user_data: rawptr) -> Bool

// ---------------------------------------------------------------------------
// Functions
// ---------------------------------------------------------------------------

@(link_prefix = "Fc", require_results)
foreign fc {
	// fcblanks.c
	BlanksCreate   :: proc() -> ^Blanks ---
	BlanksDestroy  :: proc(b: ^Blanks) ---
	BlanksAdd      :: proc(b: ^Blanks, ucs4: Char32) -> Bool ---
	BlanksIsMember :: proc(b: ^Blanks, ucs4: Char32) -> Bool ---

	// fccache.c
	CacheDir           :: proc(cache: ^Cache) -> cstring ---
	CacheCopySet       :: proc(cache: ^Cache) -> ^FontSet ---
	CacheSubdir        :: proc(cache: ^Cache, i: c.int) -> cstring ---
	CacheNumSubdir     :: proc(cache: ^Cache) -> c.int ---
	CacheNumFont       :: proc(cache: ^Cache) -> c.int ---
	DirCacheUnlink     :: proc(dir: cstring, config: ^Config) -> Bool ---
	DirCacheValid      :: proc(cache_file: cstring) -> Bool ---
	DirCacheClean      :: proc(cache_dir: cstring, verbose: Bool) -> Bool ---
	CacheCreateTagFile :: proc(config: ^Config) ---
	DirCacheCreateUUID :: proc(dir: cstring, force: Bool, config: ^Config) -> Bool ---
	DirCacheDeleteUUID :: proc(dir: cstring, config: ^Config) -> Bool ---

	// fccfg.c
	ConfigHome              :: proc() -> cstring ---
	ConfigEnableHome        :: proc(enable: Bool) -> Bool ---
	ConfigGetFilename       :: proc(config: ^Config, url: cstring) -> cstring ---
	ConfigFilename          :: proc(url: cstring) -> cstring ---
	ConfigCreate            :: proc() -> ^Config ---
	ConfigReference         :: proc(config: ^Config) -> ^Config ---
	ConfigDestroy           :: proc(config: ^Config) ---
	ConfigSetCurrent        :: proc(config: ^Config) -> Bool ---
	ConfigGetCurrent        :: proc() -> ^Config ---
	ConfigUptoDate          :: proc(config: ^Config) -> Bool ---
	ConfigBuildFonts        :: proc(config: ^Config) -> Bool ---
	ConfigGetFontDirs       :: proc(config: ^Config) -> ^StrList ---
	ConfigGetConfigDirs     :: proc(config: ^Config) -> ^StrList ---
	ConfigGetConfigFiles    :: proc(config: ^Config) -> ^StrList ---
	ConfigGetCache          :: proc(config: ^Config) -> cstring ---
	ConfigGetBlanks         :: proc(config: ^Config) -> ^Blanks ---
	ConfigGetCacheDirs      :: proc(config: ^Config) -> ^StrList ---
	ConfigGetRescanInterval :: proc(config: ^Config) -> c.int ---
	ConfigSetRescanInterval :: proc(config: ^Config, rescanInterval: c.int) -> Bool ---
	ConfigGetFonts          :: proc(config: ^Config, set: SetName) -> ^FontSet ---
	ConfigAcceptFont        :: proc(config: ^Config, font: ^Pattern) -> Bool ---
	ConfigAcceptFilename    :: proc(config: ^Config, filename: cstring) -> Bool ---
	ConfigAcceptFilter      :: proc(config: ^Config, font: ^Pattern) -> Bool ---
	ConfigAppFontAddFile    :: proc(config: ^Config, file: cstring) -> Bool ---
	ConfigAppFontAddDir     :: proc(config: ^Config, dir: cstring) -> Bool ---
	ConfigAppFontClear      :: proc(config: ^Config) ---
	ConfigPreferAppFont     :: proc(config: ^Config, flag: Bool) ---
	ConfigSetWarningFlags   :: proc(config: ^Config, warn: c.int, flag: Bool) ---
	ConfigGetWarningFlags   :: proc(config: ^Config) -> c.int ---
	ConfigSubstituteWithPat :: proc(config: ^Config, p: ^Pattern, p_pat: ^Pattern, kind: MatchKind) -> Bool ---
	ConfigSubstitute        :: proc(config: ^Config, p: ^Pattern, kind: MatchKind) -> Bool ---
	ConfigGetSysRoot        :: proc(config: ^Config) -> cstring ---
	ConfigSetSysRoot        :: proc(config: ^Config, sysroot: cstring) ---
	ConfigSetFontSetFilter  :: proc(config: ^Config, filter_func: FilterFontSetFunc, destroy_data_func: DestroyFunc, user_data: rawptr) -> ^Config ---
	ConfigFileInfoIterInit  :: proc(config: ^Config, iter: ^ConfigFileInfoIter) ---
	ConfigFileInfoIterNext  :: proc(config: ^Config, iter: ^ConfigFileInfoIter) -> Bool ---
	ConfigFileInfoIterGet   :: proc(config: ^Config, iter: ^ConfigFileInfoIter, name: ^cstring, description: ^cstring, enabled: ^Bool) -> Bool ---

	// fccharset.c
	CharSetCreate         :: proc() -> ^CharSet ---
	@(deprecated = "deprecated alias for FcCharSetCreate")
	CharSetNew            :: proc() -> ^CharSet ---
	CharSetDestroy        :: proc(fcs: ^CharSet) ---
	CharSetAddChar        :: proc(fcs: ^CharSet, ucs4: Char32) -> Bool ---
	CharSetDelChar        :: proc(fcs: ^CharSet, ucs4: Char32) -> Bool ---
	CharSetCopy           :: proc(src: ^CharSet) -> ^CharSet ---
	CharSetEqual          :: proc(a: ^CharSet, b: ^CharSet) -> Bool ---
	CharSetIntersect      :: proc(a: ^CharSet, b: ^CharSet) -> ^CharSet ---
	CharSetUnion          :: proc(a: ^CharSet, b: ^CharSet) -> ^CharSet ---
	CharSetSubtract       :: proc(a: ^CharSet, b: ^CharSet) -> ^CharSet ---
	CharSetMerge          :: proc(a: ^CharSet, b: ^CharSet, changed: ^Bool) -> Bool ---
	CharSetHasChar        :: proc(fcs: ^CharSet, ucs4: Char32) -> Bool ---
	CharSetCount          :: proc(a: ^CharSet) -> Char32 ---
	CharSetIntersectCount :: proc(a: ^CharSet, b: ^CharSet) -> Char32 ---
	CharSetSubtractCount  :: proc(a: ^CharSet, b: ^CharSet) -> Char32 ---
	CharSetIsSubset       :: proc(a: ^CharSet, b: ^CharSet) -> Bool ---
	CharSetFirstPage      :: proc(a: ^CharSet, page_map: ^[CHARSET_MAP_SIZE]Char32, next: ^Char32) -> Char32 ---
	CharSetNextPage       :: proc(a: ^CharSet, page_map: ^[CHARSET_MAP_SIZE]Char32, next: ^Char32) -> Char32 ---
	CharSetCoverage       :: proc(a: ^CharSet, page: Char32, result: ^Char32) -> Char32 ---

	// fcdbg.c
	ValuePrint   :: proc(v: Value) ---
	PatternPrint :: proc(p: ^Pattern) ---
	FontSetPrint :: proc(s: ^FontSet) ---

	// fcdefault.c
	ConfigGetDefaultLangs      :: proc(config: ^Config) -> ^StrSet ---
	GetDefaultLangs            :: proc() -> ^StrSet ---
	ConfigSetDefaultSubstitute :: proc(config: ^Config, pattern: ^Pattern) ---
	DefaultSubstitute          :: proc(pattern: ^Pattern) ---

	// fcdir.c
	FileIsDir        :: proc(file: cstring) -> Bool ---
	FileScan         :: proc(set: ^FontSet, dirs: ^StrSet, cache: ^FileCache, blanks: ^Blanks, file: cstring, force: Bool) -> Bool ---
	DirScan          :: proc(set: ^FontSet, dirs: ^StrSet, cache: ^FileCache, blanks: ^Blanks, dir: cstring, force: Bool) -> Bool ---
	DirSave          :: proc(set: ^FontSet, dirs: ^StrSet, dir: cstring) -> Bool ---
	DirCacheLoad     :: proc(dir: cstring, config: ^Config, cache_file: ^cstring) -> ^Cache ---
	DirCacheRescan   :: proc(dir: cstring, config: ^Config) -> ^Cache ---
	DirCacheRead     :: proc(dir: cstring, force: Bool, config: ^Config) -> ^Cache ---
	DirCacheLoadFile :: proc(cache_file: cstring, file_stat: rawptr) -> ^Cache --- // file_stat: struct stat *
	DirCacheUnload   :: proc(cache: ^Cache) ---

	// fcfs.c
	FontSetCreate  :: proc() -> ^FontSet ---
	FontSetDestroy :: proc(s: ^FontSet) ---
	FontSetAdd     :: proc(s: ^FontSet, font: ^Pattern) -> Bool ---

	// fcinit.c
	InitLoadConfig         :: proc() -> ^Config ---
	InitLoadConfigAndFonts :: proc() -> ^Config ---
	Init                   :: proc() -> Bool ---
	Fini                   :: proc() ---
	GetVersion             :: proc() -> c.int ---
	InitReinitialize       :: proc() -> Bool ---
	InitBringUptoDate      :: proc() -> Bool ---

	// fclang.c
	GetLangs        :: proc() -> ^StrSet ---
	LangNormalize   :: proc(lang: cstring) -> cstring ---
	LangGetCharSet  :: proc(lang: cstring) -> ^CharSet ---
	LangSetCreate   :: proc() -> ^LangSet ---
	LangSetDestroy  :: proc(ls: ^LangSet) ---
	LangSetCopy     :: proc(ls: ^LangSet) -> ^LangSet ---
	LangSetAdd      :: proc(ls: ^LangSet, lang: cstring) -> Bool ---
	LangSetDel      :: proc(ls: ^LangSet, lang: cstring) -> Bool ---
	LangSetHasLang  :: proc(ls: ^LangSet, lang: cstring) -> LangResult ---
	LangSetCompare  :: proc(lsa: ^LangSet, lsb: ^LangSet) -> LangResult ---
	LangSetContains :: proc(lsa: ^LangSet, lsb: ^LangSet) -> Bool ---
	LangSetEqual    :: proc(lsa: ^LangSet, lsb: ^LangSet) -> Bool ---
	LangSetHash     :: proc(ls: ^LangSet) -> Char32 ---
	LangSetGetLangs :: proc(ls: ^LangSet) -> ^StrSet ---
	LangSetUnion    :: proc(a: ^LangSet, b: ^LangSet) -> ^LangSet ---
	LangSetSubtract :: proc(a: ^LangSet, b: ^LangSet) -> ^LangSet ---

	// fclist.c
	ObjectSetCreate  :: proc() -> ^ObjectSet ---
	ObjectSetAdd     :: proc(os: ^ObjectSet, object: cstring) -> Bool ---
	ObjectSetDestroy :: proc(os: ^ObjectSet) ---
	ObjectSetBuild   :: proc(first: cstring, #c_vararg args: ..any) -> ^ObjectSet ---
	FontSetList      :: proc(config: ^Config, sets: [^]^FontSet, nsets: c.int, p: ^Pattern, os: ^ObjectSet) -> ^FontSet ---
	FontList         :: proc(config: ^Config, p: ^Pattern, os: ^ObjectSet) -> ^FontSet ---

	// fcatomic.c
	AtomicCreate      :: proc(file: cstring) -> ^Atomic ---
	AtomicLock        :: proc(atomic: ^Atomic) -> Bool ---
	AtomicNewFile     :: proc(atomic: ^Atomic) -> cstring ---
	AtomicOrigFile    :: proc(atomic: ^Atomic) -> cstring ---
	AtomicReplaceOrig :: proc(atomic: ^Atomic) -> Bool ---
	AtomicDeleteNew   :: proc(atomic: ^Atomic) ---
	AtomicUnlock      :: proc(atomic: ^Atomic) ---
	AtomicDestroy     :: proc(atomic: ^Atomic) ---

	// fcmatch.c
	FontSetMatch       :: proc(config: ^Config, sets: [^]^FontSet, nsets: c.int, p: ^Pattern, result: ^Result) -> ^Pattern ---
	FontMatch          :: proc(config: ^Config, p: ^Pattern, result: ^Result) -> ^Pattern ---
	FontRenderPrepare  :: proc(config: ^Config, pat: ^Pattern, font: ^Pattern) -> ^Pattern ---
	FontSetSort        :: proc(config: ^Config, sets: [^]^FontSet, nsets: c.int, p: ^Pattern, trim: Bool, csp: ^^CharSet, result: ^Result) -> ^FontSet ---
	FontSort           :: proc(config: ^Config, p: ^Pattern, trim: Bool, csp: ^^CharSet, result: ^Result) -> ^FontSet ---
	FontSetSortDestroy :: proc(fs: ^FontSet) ---

	// fcmatrix.c
	MatrixCopy     :: proc(mat: ^Matrix) -> ^Matrix ---
	MatrixEqual    :: proc(mat1: ^Matrix, mat2: ^Matrix) -> Bool ---
	MatrixMultiply :: proc(result: ^Matrix, a: ^Matrix, b: ^Matrix) ---
	MatrixRotate   :: proc(m: ^Matrix, cos: c.double, sin: c.double) ---
	MatrixScale    :: proc(m: ^Matrix, sx: c.double, sy: c.double) ---
	MatrixShear    :: proc(m: ^Matrix, sh: c.double, sv: c.double) ---

	// fcname.c
	@(deprecated = "Does nothing.  Returns FcFalse")
	NameRegisterObjectTypes   :: proc(types: ^ObjectType, ntype: c.int) -> Bool ---
	@(deprecated = "Does nothing.  Returns FcFalse")
	NameUnregisterObjectTypes :: proc(types: ^ObjectType, ntype: c.int) -> Bool ---
	NameGetObjectType         :: proc(object: cstring) -> ^ObjectType ---
	@(deprecated = "Does nothing.  Returns FcFalse")
	NameRegisterConstants     :: proc(consts: ^Constant, nconsts: c.int) -> Bool ---
	@(deprecated = "Does nothing.  Returns FcFalse")
	NameUnregisterConstants   :: proc(consts: ^Constant, nconsts: c.int) -> Bool ---
	NameGetConstant           :: proc(string: cstring) -> ^Constant ---
	NameGetConstantFor        :: proc(string: cstring, object: cstring) -> ^Constant ---
	NameConstant              :: proc(string: cstring, result: ^c.int) -> Bool ---
	NameGetConstantNameFrom   :: proc(object: cstring, value: c.int) -> cstring ---
	NameParse                 :: proc(name: cstring) -> ^Pattern ---
	NameUnparse               :: proc(pat: ^Pattern) -> cstring ---

	// fcpat.c
	PatternCreate         :: proc() -> ^Pattern ---
	PatternDuplicate      :: proc(p: ^Pattern) -> ^Pattern ---
	PatternReference      :: proc(p: ^Pattern) ---
	PatternFilter         :: proc(p: ^Pattern, os: ^ObjectSet) -> ^Pattern ---
	ValueDestroy          :: proc(v: Value) ---
	ValueEqual            :: proc(va: Value, vb: Value) -> Bool ---
	ValueSave             :: proc(v: Value) -> Value ---
	PatternDestroy        :: proc(p: ^Pattern) ---
	PatternObjectCount    :: proc(pat: ^Pattern) -> c.int ---
	PatternEqual          :: proc(pa: ^Pattern, pb: ^Pattern) -> Bool ---
	PatternEqualSubset    :: proc(pa: ^Pattern, pb: ^Pattern, os: ^ObjectSet) -> Bool ---
	PatternHash           :: proc(p: ^Pattern) -> Char32 ---
	PatternAdd            :: proc(p: ^Pattern, object: cstring, value: Value, append: Bool) -> Bool ---
	PatternAddWeak        :: proc(p: ^Pattern, object: cstring, value: Value, append: Bool) -> Bool ---
	PatternGet            :: proc(p: ^Pattern, object: cstring, id: c.int, v: ^Value) -> Result ---
	PatternGetWithBinding :: proc(p: ^Pattern, object: cstring, id: c.int, v: ^Value, b: ^ValueBinding) -> Result ---
	PatternDel            :: proc(p: ^Pattern, object: cstring) -> Bool ---
	PatternRemove         :: proc(p: ^Pattern, object: cstring, id: c.int) -> Bool ---
	PatternAddInteger     :: proc(p: ^Pattern, object: cstring, i: c.int) -> Bool ---
	PatternAddDouble      :: proc(p: ^Pattern, object: cstring, d: c.double) -> Bool ---
	PatternAddString      :: proc(p: ^Pattern, object: cstring, s: cstring) -> Bool ---
	PatternAddMatrix      :: proc(p: ^Pattern, object: cstring, s: ^Matrix) -> Bool ---
	PatternAddCharSet     :: proc(p: ^Pattern, object: cstring, cs: ^CharSet) -> Bool ---
	PatternAddBool        :: proc(p: ^Pattern, object: cstring, b: Bool) -> Bool ---
	PatternAddLangSet     :: proc(p: ^Pattern, object: cstring, ls: ^LangSet) -> Bool ---
	PatternAddRange       :: proc(p: ^Pattern, object: cstring, r: ^Range) -> Bool ---
	PatternGetInteger     :: proc(p: ^Pattern, object: cstring, n: c.int, i: ^c.int) -> Result ---
	PatternGetDouble      :: proc(p: ^Pattern, object: cstring, n: c.int, d: ^c.double) -> Result ---
	PatternGetString      :: proc(p: ^Pattern, object: cstring, n: c.int, s: [^]cstring) -> Result ---
	PatternGetMatrix      :: proc(p: ^Pattern, object: cstring, n: c.int, s: ^^Matrix) -> Result ---
	PatternGetCharSet     :: proc(p: ^Pattern, object: cstring, n: c.int, cs: ^^CharSet) -> Result ---
	PatternGetBool        :: proc(p: ^Pattern, object: cstring, n: c.int, b: ^Bool) -> Result ---
	PatternGetLangSet     :: proc(p: ^Pattern, object: cstring, n: c.int, ls: ^^LangSet) -> Result ---
	PatternGetRange       :: proc(p: ^Pattern, object: cstring, id: c.int, r: ^^Range) -> Result ---
	PatternBuild          :: proc(p: ^Pattern, #c_vararg args: ..any) -> ^Pattern ---
	PatternFormat         :: proc(pat: ^Pattern, format: cstring) -> cstring ---

	// fcrange.c
	RangeCreateDouble  :: proc(begin: c.double, end: c.double) -> ^Range ---
	RangeCreateInteger :: proc(begin: Char32, end: Char32) -> ^Range ---
	RangeDestroy       :: proc(range: ^Range) ---
	RangeCopy          :: proc(r: ^Range) -> ^Range ---
	RangeGetDouble     :: proc(range: ^Range, begin: ^c.double, end: ^c.double) -> Bool ---

	PatternIterStart      :: proc(pat: ^Pattern, iter: ^PatternIter) ---
	PatternIterNext       :: proc(pat: ^Pattern, iter: ^PatternIter) -> Bool ---
	PatternIterEqual      :: proc(p1: ^Pattern, i1: ^PatternIter, p2: ^Pattern, i2: ^PatternIter) -> Bool ---
	PatternFindIter       :: proc(pat: ^Pattern, iter: ^PatternIter, object: cstring) -> Bool ---
	PatternIterIsValid    :: proc(pat: ^Pattern, iter: ^PatternIter) -> Bool ---
	PatternIterGetObject  :: proc(pat: ^Pattern, iter: ^PatternIter) -> cstring ---
	PatternIterValueCount :: proc(pat: ^Pattern, iter: ^PatternIter) -> c.int ---
	PatternIterGetValue   :: proc(pat: ^Pattern, iter: ^PatternIter, id: c.int, v: ^Value, b: ^ValueBinding) -> Result ---

	// fcweight.c
	WeightFromOpenType       :: proc(ot_weight: c.int) -> c.int ---
	WeightFromOpenTypeDouble :: proc(ot_weight: c.double) -> c.double ---
	WeightToOpenType         :: proc(fc_weight: c.int) -> c.int ---
	WeightToOpenTypeDouble   :: proc(fc_weight: c.double) -> c.double ---

	// fcstr.c
	StrCopy           :: proc(s: cstring) -> cstring ---
	StrCopyFilename   :: proc(s: cstring) -> cstring ---
	StrPlus           :: proc(s1: cstring, s2: cstring) -> cstring ---
	StrFree           :: proc(s: cstring) ---
	StrDowncase       :: proc(s: cstring) -> cstring ---
	StrCmpIgnoreCase  :: proc(s1: cstring, s2: cstring) -> c.int ---
	StrCmp            :: proc(s1: cstring, s2: cstring) -> c.int ---
	StrStrIgnoreCase  :: proc(s1: cstring, s2: cstring) -> cstring ---
	StrStr            :: proc(s1: cstring, s2: cstring) -> cstring ---
	Utf8ToUcs4        :: proc(src_orig: cstring, dst: ^Char32, len: c.int) -> c.int ---
	Utf8Len           :: proc(string: cstring, len: c.int, nchar: ^c.int, wchar: ^c.int) -> Bool ---
	Ucs4ToUtf8        :: proc(ucs4: Char32, dest: ^[UTF8_MAX_LEN]Char8) -> c.int ---
	Utf16ToUcs4       :: proc(src_orig: cstring, endian: Endian, dst: ^Char32, len: c.int) -> c.int ---
	Utf16Len          :: proc(string: cstring, endian: Endian, len: c.int, nchar: ^c.int, wchar: ^c.int) -> Bool ---
	StrBuildFilename  :: proc(path: cstring, #c_vararg args: ..any) -> cstring ---
	StrDirname        :: proc(file: cstring) -> cstring ---
	StrBasename       :: proc(file: cstring) -> cstring ---
	StrSetCreate      :: proc() -> ^StrSet ---
	StrSetMember      :: proc(set: ^StrSet, s: cstring) -> Bool ---
	StrSetEqual       :: proc(sa: ^StrSet, sb: ^StrSet) -> Bool ---
	StrSetAdd         :: proc(set: ^StrSet, s: cstring) -> Bool ---
	StrSetAddFilename :: proc(set: ^StrSet, s: cstring) -> Bool ---
	StrSetDel         :: proc(set: ^StrSet, s: cstring) -> Bool ---
	StrSetDestroy     :: proc(set: ^StrSet) ---
	StrListCreate     :: proc(set: ^StrSet) -> ^StrList ---
	StrListFirst      :: proc(list: ^StrList) ---
	StrListNext       :: proc(list: ^StrList) -> cstring ---
	StrListDone       :: proc(list: ^StrList) ---

	// fcxml.c
	ConfigParseAndLoad           :: proc(config: ^Config, file: cstring, complain: Bool) -> Bool ---
	ConfigParseAndLoadFromMemory :: proc(config: ^Config, buffer: [^]Char8, complain: Bool) -> Bool ---

	// fcconffile.c
	ConfigFileGenerate :: proc(config: ^Config, pat: ^Pattern, font_path: cstring) -> cstring ---
}

// ---------------------------------------------------------------------------
// ASCII-only helpers (suitable only for pattern element names), matching the
// FcIsUpper / FcIsLower / FcToLower macros in the C header.
// ---------------------------------------------------------------------------

IsUpper :: #force_inline proc(ch: u8) -> bool {
	return 0o101 <= ch && ch <= 0o132
}

IsLower :: #force_inline proc(ch: u8) -> bool {
	return 0o141 <= ch && ch <= 0o172
}

ToLower :: #force_inline proc(ch: u8) -> u8 {
	return (ch - 0o101 + 0o141) if IsUpper(ch) else ch
}
