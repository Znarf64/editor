#+feature dynamic-literals
package editor

import runtime "base:runtime"

import fmt     "core:fmt"
import json    "core:encoding/json"
import log     "core:log"
import os      "core:os"
import strings "core:strings"
import vmem    "core:mem/virtual"

LSP_Error :: union #shared_nil {
	os.Error,
	json.Error,
	json.Unmarshal_Error,
	json.Marshal_Error,
}

LSP_Server :: struct {
	language:       Language,
	process:        os.Process,
	stdin, stdout: ^os.File,
	read_buf:       [dynamic]byte,
	request_id:     int,
	responses:      map[int]LSP_Response_Proc,
	capabilities:   Server_Capabilities,
	initialized:    bool,
	pending_files:  map[Uri]struct{}, // files opened before the server is initialized
	arena:          vmem.Arena,
}

LSP_Response_Proc :: proc(editor: ^Editor, lsp_server: ^LSP_Server, content: []byte) -> LSP_Error

@(require_results)
send_request :: proc(lsp: ^LSP_Server, name: string, params: $Params, response: LSP_Response_Proc) -> (error: LSP_Error) {
	lsp.request_id += 1

	data := Request(Params) {
		jsonrpc = "2.0",
		method  = name,
		id      = lsp.request_id,
		params  = params,
	}

	lsp.responses[lsp.request_id] = response

	return jrpc_send_message(lsp, data)
}

@(require_results)
send_notification :: proc(lsp: ^LSP_Server, name: string, params: $Params) -> (error: LSP_Error) {
	data := Notification(Params) {
		jsonrpc = "2.0",
		method  = name,
		params  = params,
	}

	return jrpc_send_message(lsp, data)
}

@(require_results)
lsp_init :: proc(lsp: ^LSP_Server, command: []string) -> (err: LSP_Error) {
	vmem.arena_init_growing(&lsp.arena) or_else panic("Failed to create arena")

	desc: os.Process_Desc = {
		command = command,
	}
	desc.stdin, lsp.stdin   = os.pipe() or_return
	lsp.stdout, desc.stdout = os.pipe() or_return

	lsp.process = os.process_start(desc) or_return

	os.close(desc.stdin)
	os.close(desc.stdout)

	send_request(
		lsp,
		"initialize",
		Initialize_Request_Params {
			clientInfo = {
				name = "Editor",
			},
			capabilities = {
				general = {
					positionEncodings = { "utf-8", },
				},
				textDocument = {
					hover = { contentFormat = { "markdown", "plaintext", }, },
				},
			},
		},
		proc(editor: ^Editor, lsp_server: ^LSP_Server, content: []byte) -> LSP_Error {
			allocator := vmem.arena_allocator(&lsp_server.arena)

			response: Response(Initialize_Result)
			err := json.unmarshal(content, &response, allocator = allocator)
			if err != nil {
				return err
			}

			send_notification(lsp_server, "initialized", struct{}{}) or_return

			lsp_server.initialized  = true
			lsp_server.capabilities = response.result.capabilities

			for uri in lsp_server.pending_files {
				path := uri_to_path(uri, context.temp_allocator) or_else panic("")
				data := os.read_entire_file(path, context.temp_allocator) or_continue
				lsp_open_file(lsp_server, uri, string(data))
			}
			delete(lsp_server.pending_files)
			lsp_server.pending_files = {}

			log.info("LSP server initialized")
			log.debug("LSP server capabilities:", lsp_server.capabilities)

			return nil
		},
	) or_return

	return
} 

lsp_destroy :: proc(lsp: ^LSP_Server) {
	vmem.arena_destroy(&lsp.arena)
	_ = os.process_kill(lsp.process)
	os.close(lsp.stdout)
	os.close(lsp.stdin)
	delete(lsp.responses)
	delete(lsp.read_buf)
}

Diagnostic_Severity :: enum {
	Error       = 1,
	Warning     = 2,
	Information = 3,
	Hint        = 4,
}

LSP_Position :: struct {
	line, character: int,
}

Location :: struct {
	uri:   Uri,
	range: LSP_Range,
}

Location_Link :: struct {
	originSelectionRange: LSP_Range,
	targetUri:            Uri,
	targetRange:          LSP_Range,
	targetSelectionRange: LSP_Range,
}

Fused_Location :: struct {
	using _: Location_Link,
	using _: Location,
}

LSP_Range :: struct {
	start, end: LSP_Position,
}

LSP_Diagnostic :: struct {
	range:    LSP_Range,
	message:  string,
	code:     string,
	severity: Maybe(Diagnostic_Severity),
}

Publish_Diagnositics_Params :: struct {
	uri:         Uri,
	version:     Maybe(int),
	diagnostics: []LSP_Diagnostic,
}

lsp_methods: map[string]proc(editor: ^Editor, content: []byte) = {
	"window/logMessage" = proc(editor: ^Editor, content: []byte) {
		notification: Notification(struct {
			type:    Message_Type,
			message: string,
		})
		json.unmarshal(content, &notification, allocator = context.temp_allocator)
	},
	"textDocument/publishDiagnostics" = proc(editor: ^Editor, content: []byte) {
		notification: Notification(Publish_Diagnositics_Params)
		json.unmarshal(content, &notification, allocator = context.temp_allocator)

		if editor.buffer.uri != notification.params.uri {
			return
		}

		vmem.arena_free_all(&editor.buffer.diagnostics_arena)
		allocator                := vmem.arena_allocator(&editor.buffer.diagnostics_arena)
		editor.buffer.diagnostics = make([]Diagnostic, len(notification.params.diagnostics), allocator)
		for &d, i in editor.buffer.diagnostics {
			diagnostic := notification.params.diagnostics[i]
			if diagnostic.range.end.character > 0 {
				diagnostic.range.end.character -= 1
			}
			d = {
				code     = strings.clone(diagnostic.code,    allocator),
				message  = strings.clone(diagnostic.message, allocator),
				start    = lsp_position_to_offset(&editor.buffer.btree, diagnostic.range.start),
				end      = lsp_position_to_offset(&editor.buffer.btree, diagnostic.range.end),
				severity = diagnostic.severity.? or_else .Error,
			}
		}
	},
}

Text_Document_Identifier :: struct {
	uri: Uri,
}

Did_Open_Text_Document_Params :: struct {
	textDocument: Text_Document_Item,
}

Text_Document_Item :: struct {
	/**
	 * The text document's URI.
	 */
	uri: Uri,

	/**
	 * The text document's language identifier.
	 */
	languageId: string `json:,omitempty`,

	/**
	 * The version number of this document (it will increase after each
	 * change, including undo/redo).
	 */
	version: int,

	/**
	 * The content of the opened text document.
	 */
	text: string,
}

Did_Save_Text_Document_Params :: struct {
	textDocument: Text_Document_Identifier,
	text:         Maybe(string),
}

Text_Document_Position_Params :: struct {
	textDocument: Text_Document_Identifier,
	position:     LSP_Position,
}

lsp_open_file :: proc(lsp: ^LSP_Server, uri: Uri, content: string) {
	if !lsp.initialized {
		if uri not_in lsp.pending_files {
			lsp.pending_files[uri] = {}
		}
		return
	}

	_ = send_notification(lsp, "textDocument/didOpen", Did_Open_Text_Document_Params {
		textDocument = {
			languageId = string(lsp.language),
			uri        = uri,
			text       = content,
		},
	})

	_ = send_notification(lsp, "textDocument/didSave", Did_Save_Text_Document_Params {
		textDocument = {
			uri = uri,
		},
	})
}

Versioned_Text_Document_Identifier :: struct {
	using _: Text_Document_Identifier,
	version: int,
}

Text_Document_Content_Change_Event :: struct {
	/**
	 * The range of the document that changed.
	 */
	range: LSP_Range,

	/**
	 * The new text for the provided range.
	 */
	text: string,
}

Did_Change_Text_Document_Params :: struct {
	textDocument:     Versioned_Text_Document_Identifier,
	contentChanges: []Text_Document_Content_Change_Event,
}

lsp_apply_change :: proc(lsp: ^LSP_Server, buffer: ^Buffer, start, end: Offset, text: string, version: int) {
	change := Text_Document_Content_Change_Event {
		range = { start = offset_to_lsp_position(&buffer.btree, start), end = offset_to_lsp_position(&buffer.btree, end), },
		text  = text,
	}
	_ = send_notification(lsp, "textDocument/didChange", Did_Change_Text_Document_Params {
		textDocument   = { uri = buffer.uri, version = version, },
		contentChanges = { change, },
	})
}

lsp_save :: proc(lsp: ^LSP_Server, buffer: ^Buffer) {
	_ = send_notification(lsp, "textDocument/didSave", Did_Save_Text_Document_Params {
		textDocument = { uri = buffer.uri, },
	})
}

lsp_go_to_definition :: proc(editor: ^Editor, buffer: ^Buffer_View) {
	lsp := editor_get_lsp_server(editor, buffer.language)
	if lsp == nil || !lsp.initialized {
		editor_set_status(editor, "No lsp server available")
		return
	}

	cursor     := buffer.selections[buffer.primary].cursor
	position   := btree_offset_to_position(&buffer.btree, cursor)
	line_start := btree_line_to_offset(&buffer.btree, position.line)
	_ = send_request(lsp, "textDocument/definition", Text_Document_Position_Params {
		textDocument = { uri = buffer.uri, },
		position     = {
			line      = position.line,
			character = int(cursor - line_start),
		},
	}, proc(editor: ^Editor, lsp_server: ^LSP_Server, content: []byte) -> LSP_Error {
		response: Response(union {
			Location,
			// since we don't know whether its all links or locations, but both would be unmarshalled without errors so we do this goofy business
			[]Fused_Location,
		})
		json.unmarshal(content, &response, allocator = context.temp_allocator) or_return

		location: Location
		switch v in response.result {
		case Location:
			location = v
		case []Fused_Location:
			if len(v) == 0 {
				return nil
			}
			if len(v) == 1 {
				location = v[0]
				if location == {} {
					location = { uri = v[0].targetUri, range = v[0].targetRange, }
				}
				break
			}

			picker_open(editor, .Symbols, fused_locations = v)
			return nil
		case nil:
			return nil
		}

		path, ok := uri_to_path(location.uri, context.temp_allocator)
		if !ok {
			return nil
		}

		if location.range.end.character > 0 {
			location.range.end.character -= 1
		}

		file_open(editor, normalize_path(path, context.temp_allocator))

		start := lsp_position_to_offset(&editor.buffer.btree, location.range.start)
		end   := lsp_position_to_offset(&editor.buffer.btree, location.range.end)

		editor_go_to(editor, "", start, end)

		jumplist_add(editor, editor.buffer.selections[editor.buffer.primary])

		return nil
	})
}

Markup_Kind :: distinct string

Markup_Content :: struct {
	kind:  Markup_Kind,
	value: string,
}

lsp_get_hover_information :: proc(editor: ^Editor, buffer: ^Buffer_View) {
	lsp := editor_get_lsp_server(editor, buffer.language)
	if lsp == nil || !lsp.initialized {
		editor_set_status(editor, "No lsp server available")
		return
	}
	cursor     := buffer.selections[buffer.primary].cursor
	position   := btree_offset_to_position(&buffer.btree, cursor)
	line_start := btree_line_to_offset(&buffer.btree, position.line)
	_ = send_request(lsp, "textDocument/hover", Text_Document_Position_Params {
		textDocument = { uri = buffer.uri, },
		position     = {
			line      = position.line,
			character = int(cursor - line_start),
		},
	}, proc(editor: ^Editor, lsp: ^LSP_Server, content: []byte) -> LSP_Error {
		response: Response(struct {
			contents: union {
				Markup_Content,
				string,
			},
		})
		json.unmarshal(content, &response, allocator = context.temp_allocator) or_return

		switch v in response.result.contents {
		case Markup_Content:
			editor_set_popup_text(editor, .Markdown, "%v", v.value)
		case string:
			editor_set_popup_text(editor, .Code, "%v", v)
		}
		return nil
	})
}

lsp_get_signature_help :: proc(editor: ^Editor, buffer: ^Buffer_View) {
	lsp := editor_get_lsp_server(editor, buffer.language)
	if lsp == nil || !lsp.initialized {
		editor_set_status(editor, "No lsp server available")
		return
	}

	cursor     := buffer.selections[buffer.primary].cursor
	position   := btree_offset_to_position(&buffer.btree, cursor)
	line_start := btree_line_to_offset(&buffer.btree, position.line)
	_ = send_request(lsp, "textDocument/signatureHelp", Signature_Help_Params {
		textDocument = { uri = buffer.uri, },
		position     = {
			line      = position.line,
			character = int(cursor - line_start),
		},
	}, proc(editor: ^Editor, lsp: ^LSP_Server, content: []byte) -> LSP_Error {
		response: Response(Signature_Help)
		json.unmarshal(content, &response, allocator = context.temp_allocator) or_return

		if len(response.result.signatures) == 0 {
			editor_set_popup_text(editor, .Text, "", location = .Above)
			return nil
		}

		signature := response.result.signatures[response.result.activeSignature]
		highlight: Range
		if len(signature.parameters) > response.result.activeParameter {
			switch v in signature.parameters[response.result.activeParameter].label {
			case string:
				highlight.start = Offset(strings.index(signature.label, v))
				highlight.end   = highlight.start + Offset(len(v))
			case [2]int:
				highlight = {
					start = Offset(v[0]),
					end   = Offset(v[1]),
				}
			}
		}

		editor_set_popup_text(editor, .Code, "%s", signature.label, location = .Above, highlight = highlight)

		return nil
	})
}

lsp_get_completion :: proc(editor: ^Editor, buffer: ^Buffer_View) {
	lsp := editor_get_lsp_server(editor, buffer.language)
	if lsp == nil || !lsp.initialized {
		editor_set_status(editor, "No lsp server available")
		return
	}

	cursor     := buffer.selections[buffer.primary].cursor
	position   := btree_offset_to_position(&buffer.btree, cursor)
	line_start := btree_line_to_offset(&buffer.btree, position.line)
	_ = send_request(lsp, "textDocument/completion", Text_Document_Position_Params {
		textDocument = { uri = buffer.uri, },
		position     = {
			line      = position.line,
			character = int(cursor - line_start),
		},
	}, proc(editor: ^Editor, lsp: ^LSP_Server, content: []byte) -> LSP_Error {
		Edit_Range_With_Insert_Replace :: struct {
			insert, replace: LSP_Range,
		}
		Completion_Item_Defaults :: struct {
			commitCharacters: []string,
			editRange:        union { LSP_Range, Edit_Range_With_Insert_Replace, },
			insertTextFormat: string,
			insertTextMode:   string,
		}

		Completion_List :: struct {
			isIncomplete: bool,
			itemDefaults: Completion_Item_Defaults,
			items:        []Completion_Item,
		}

		Completion_Item :: struct {
			label: string,
			// labelDetails: CompletionItemLabelDetails,
			// kind: CompletionItemKind,
			// tags: CompletionItemTag[],
			detail: string,
			documentation: union{ string, Markup_Content, },
			preselect: bool,
			// sortText: string,
			// filterText: string,
			// insertText: string,
			// insertTextFormat: InsertTextFormat,
			// insertTextMode: InsertTextMode,
			textEdit: union{ Text_Edit, Insert_Replace_Edit, },
			textEditText: string,
			// additionalTextEdits: TextEdit[],
			// commitCharacters: string[],
			// command: Command,
		}
		response: Response(union {
			[]Completion_Item,
			Completion_List,
		})
		json.unmarshal(content, &response, allocator = context.temp_allocator) or_return

		b := strings.builder_make(context.temp_allocator)
		switch v in response.result {
		case []Completion_Item:
			for item in v {
				fmt.sbprintln(&b, item.label)
			}
		case Completion_List:
			for item in v.items {
				fmt.sbprintln(&b, item.label)
			}
		}

		if strings.builder_len(b) != 0 {
			editor_set_popup_text(editor, .Text, "%s", strings.to_string(b), location = .Below)
		}

		return nil
	})
}

Text_Edit :: struct {
	range:   LSP_Range,
	newText: string,
}

Insert_Replace_Edit :: struct {
	insert:  LSP_Range,
	replace: LSP_Range,
	newText: string,
}

@(require_results)
lsp_update :: proc(editor: ^Editor, lsp: ^LSP_Server) -> LSP_Error {
	for os.pipe_has_data(lsp.stdout) or_return {
		READ_CHUNK_SIZE :: 1 << 12

		l := len(lsp.read_buf)
		resize(&lsp.read_buf, l + READ_CHUNK_SIZE)
		n := os.read(lsp.stdout, lsp.read_buf[l:]) or_return
		resize(&lsp.read_buf, l + n)
	}

	read_cursor := 0

	for {
		data := lsp.read_buf[read_cursor:]
		method, id, content, n, ok := jrpc_decode_message(data)
		if !ok {
			return json.Error.Unexpected_Token
		}
		if n == 0 {
			break
		}
		read_cursor += n

		if id != 0 {
			if method != "" {
				log.warn("LSP: ignoring request from server:", method)
				continue
			}

			_, fn := delete_key(&lsp.responses, id)
			if fn == nil {
				log.error("LSP: Invalid response id:", id, method)
			} else {
				fn(editor, lsp, content) or_return
			}
			continue
		}

		fn, found := lsp_methods[method]
		if !found {
			log.warn("Unknown lsp method:", method)
			continue
		}

		fn(editor, content)
	}

	copy(lsp.read_buf[:], lsp.read_buf[read_cursor:])
	resize(&lsp.read_buf, len(lsp.read_buf) - read_cursor)

	return nil
}

Message_Type :: enum {
	/**
	 * An error message.
	 */
	Error = 1,
	/**
	 * A warning message.
	 */
	Warning = 2,
	/**
	 * An information message.
	 */
	Info = 3,
	/**
	 * A log message.
	 */
	Log = 4,
	/**
	 * A debug message.
	 *
	 * @since 3.18.0
	 */
	Debug = 5,
}

Notification :: struct($Params: typeid) {
	using _: Base_Notification,
	params:  Params,
}

Base_Notification :: struct {
	jsonrpc: string,
	method:  string,
}

Base_Request :: struct {
	jsonrpc: string,
	id:      int,
	method:  string,
}

Request :: struct($Params: typeid) {
	using _: Base_Request,
	params:  Params,
}

Client_Capabilities :: struct {
	general: struct {
		positionEncodings: []string,
	},
	textDocument: struct {
		hover: struct { contentFormat: []string, },
	},
}

Initialize_Request_Params :: struct {
	clientInfo: struct {
		name:    string,
		version: Maybe(string),
	},
	capabilities: Client_Capabilities,
}

Base_Response :: struct {
	jsonrpc: string,
	id:      Maybe(int),
}

Response :: struct($Result: typeid) {
	using _: Base_Response,
	result:  Result,
}

Text_Document_Sync_Kind :: enum {
	None        = 0,
	Full        = 1,
	Incremental = 2,
}

Completion_Options :: struct {
	triggerCharacters: []string,
}

Signature_Help_Options :: struct {
	triggerCharacters:   []string,
	retriggerCharacters: []string,
}

Server_Info :: struct {
	name:    string,
	version: string,
}

Text_Document_Sync_Options :: struct {
	openClose: bool,
	change:    Text_Document_Sync_Kind,
}

Server_Capabilities :: struct {
	positionEncoding: string,
	textDocumentSync: union {
		Text_Document_Sync_Kind,
		Text_Document_Sync_Options,
	},
	completionProvider: Maybe(struct {
		triggerCharacters: []string,
	}),
	hoverProvider: union {
		bool,
		json.Value,
	},
	signatureHelpProvider: Maybe(struct {
		triggerCharacters:   []string,
		retriggerCharacters: []string,
	}),
	declarationProvider:       union { bool, Declaration_Registration_Options,     },
	definitionProvider:        union { bool, Definition_Options,                   },
	typeDefinitionProvider:    union { bool, Type_Definition_Registration_Options, },
	implementationProvider:    union { bool, Implementation_Registration_Options,  },
	referencesProvider:        union { bool, Reference_Options,                    },
	documentHighlightProvider: union { bool, Document_Highlight_Options,           },
	documentSymbolProvider:    union { bool, Document_Symbol_Options,              },
	codeActionProvider:        union { bool, Code_Action_Options,                  },
	renameProvider:            union { bool, Rename_Options,                       },
}

Declaration_Registration_Options     :: struct {}
Definition_Options                   :: struct {}
Type_Definition_Registration_Options :: struct {}
Implementation_Registration_Options  :: struct {}
Reference_Options                    :: struct {}
Document_Highlight_Options           :: struct {}
Document_Symbol_Options              :: struct { label: bool, }
Code_Action_Options                  :: struct {}
Rename_Options                       :: struct {}

Initialize_Result :: struct {
	capabilities: Server_Capabilities,
	serverInfo:   Server_Info,
}

@(require_results)
lsp_position_to_offset :: proc(btree: ^BTree, position: LSP_Position) -> Offset {
	offset := btree_line_to_offset(btree, position.line)
	return btree_offset_after(btree, offset, position.character)
}

@(require_results)
offset_to_lsp_position :: proc(btree: ^BTree, offset: Offset) -> (position: LSP_Position) {
	position.line = btree_offset_to_line(btree, offset)
	iter         := btree_iterator(btree, line = position.line)

	for iter.next_offset != offset {
		_ = btree_iter(&iter) or_else panic("offset out of range")
		position.character += 1
	}

	return
}

Signature_Help_Params :: struct {
	using _:  Text_Document_Position_Params,
	context_: Signature_Help_Context `json:"context"`,
}

Signature_Help_Trigger_Kind :: enum int {
	Invoked          = 1,
	TriggerCharacter = 2,
	ContentChange    = 3,
}

Signature_Help_Context :: struct {
	triggerKind:         Signature_Help_Trigger_Kind,
	triggerCharacter:    string,
	isRetrigger:         bool,
	activeSignatureHelp: Signature_Help,
}

Signature_Help :: struct {
	signatures:      []Signature_Information,
	activeSignature: int,
	activeParameter: int,
}

Signature_Information :: struct {
	label:           string,
	documentation:   union { string, Markup_Content, },
	parameters:      []Parameter_Information,
	activeParameter: int,
}

Parameter_Information :: struct {
	label:         union { string, [2]int,         },
	documentation: union { string, Markup_Content, },
}
