package test

import fmt     "core:fmt"
import os      "core:os"
import strings "core:strings"

import fc ".."

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintfln(`usage: %s "Font Name"`, os.args[0])
		return
	}

	config := fc.InitLoadConfigAndFonts()
	defer fc.Fini()
	defer fc.ConfigDestroy(config)

	pattern := fc.NameParse(strings.clone_to_cstring(os.args[1], context.temp_allocator))
	defer fc.PatternDestroy(pattern)

	if pattern == nil {
		fmt.eprintln("Failed to parse pattern")
		return
	}

	if !fc.ConfigSubstitute(config, pattern, .Pattern) {
		fmt.eprintln("Failed to substitute pattern")
		return
	}
	fc.DefaultSubstitute(pattern)

	fs := fc.FontSetCreate()
	defer fc.FontSetDestroy(fs)

	os := fc.ObjectSetBuild(fc.FAMILY, fc.STYLE, fc.FILE, nil)
	defer fc.ObjectSetDestroy(os)

	result: fc.Result
	font_patterns := fc.FontSort(config, pattern, true, nil, &result)
	defer fc.FontSetSortDestroy(font_patterns)

	if font_patterns == nil || font_patterns.nfont == 0 {
		fmt.eprintln("Fontconfig could not find ANY fonts on the system?")
		return
	}

	font_pattern := fc.FontRenderPrepare(config, pattern, font_patterns.fonts[0])
	if font_pattern == nil {
		fmt.eprintln("Could not prepare matched font for loading.")
		return
	}

	if !fc.FontSetAdd(fs, font_pattern) {
		fmt.eprintln("Failed to add matched font to font set")
		return
	}

	if fs == nil {
		fmt.eprintln("Could not obtain fs")
		return
	}

	if fs.nfont > 0 {
		font := fc.PatternFilter(fs.fonts[0], os)
		defer fc.PatternDestroy(font)

		v: fc.Value
		_ = fc.PatternGet(font, fc.FILE, 0, &v)

		filepath := cstring(v.u.f)
		fmt.printfln("Path: %s", filepath)
	}
}
