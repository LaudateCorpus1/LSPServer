(* ::Package::"Tags"-><|"NoVariables" -> <|"Module" -> <|Enabled -> False|>|>|>:: *)

BeginPackage["LSPServer`"]

StartServer::usage = "StartServer[] puts the kernel into a state ready for traffic from the client.\
 StartServer[logDir] logs traffic to logDir."

RunServerDiagnostic

initializeLSPComm

expandContent

expandContentsAndAppendToContentQueue

LSPEvaluate
readEvalWriteLoop

ProcessScheduledJobs


exitHard
exitGracefully
exitSemiGracefully
shutdownLSPComm


handleContent

handleContentAfterShutdown



$Debug

$Debug2

$Debug3

$DebugBracketMatcher


$PreExpandContentQueue

$ContentQueue

$OpenFilesMap

$CancelMap

$hrefIdCounter

$ServerState


$AllowedImplicitTokens


$BracketMatcher

(*
$BracketMatcherDisplayInsertionText
*)

$BracketMatcherUseDesignColors


$ConfidenceLevel

$HierarchicalDocumentSymbolSupport

(*
$SemanticTokens is True if the client supports semantic tokens and the user has enabled them

If $SemanticTokens is False, then diagnostics are used as a fallback to indicate scoping issues such as unused variables and shadowed variables

*)
$SemanticTokens


$ML4CodeTimeLimit

$commProcess



$BracketMatcherDelayAfterLastChange
$DiagnosticsDelayAfterLastChange
$ImplicitTokensDelayAfterLastChange


$startupMessagesText


Begin["`Private`"]


(*
setup Startup Messages handling

There may be internal errors in LSPServer that emit messages during Needs["LSPServer`"]

These messages are exceptionally hard to handle because any code for handling has not yet been loaded

The messages may cause unexplained hangs in clients

So manually set $Messages to a tmp file and then handle the messages later
*)
$startupMessagesFile = OpenWrite[]

If[!FailureQ[$startupMessagesFile],
  $oldMessages = $Messages;
  $Messages = {$startupMessagesFile}
  ,
  $startupMessagesText = "OpenWrite[] failed while setting up Startup Messages handling"
]



Needs["LSPServer`BracketMismatches`"]
Needs["LSPServer`CodeAction`"]
Needs["LSPServer`Color`"]
Needs["LSPServer`Definitions`"]
Needs["LSPServer`Diagnostics`"]
Needs["LSPServer`DocumentSymbol`"]
Needs["LSPServer`Formatting`"]
Needs["LSPServer`Hover`"]
Needs["LSPServer`ImplicitTokens`"]
Needs["LSPServer`Library`"]
Needs["LSPServer`ListenSocket`"]
Needs["LSPServer`References`"]
Needs["LSPServer`SelectionRange`"]
Needs["LSPServer`SemanticTokens`"]
Needs["LSPServer`ServerDiagnostics`"]
Needs["LSPServer`Socket`"]
Needs["LSPServer`StdIO`"]
Needs["LSPServer`Utils`"]
Needs["LSPServer`Workspace`"]

Needs["CodeFormatter`"]
Needs["CodeInspector`"]
Needs["CodeInspector`Format`"]
Needs["CodeInspector`ImplicitTokens`"]
Needs["CodeInspector`BracketMismatches`"]
Needs["CodeInspector`Utils`"]
Needs["CodeParser`"]
Needs["CodeParser`Utils`"]

Needs["PacletManager`"] (* for PacletInformation *)


(*
TODO: when targeting 12.1 as a minimum, then use paclet["AssetLocation", "BuiltInFunctions"]
*)
location = "Location" /. PacletInformation["LSPServer"];

WolframLanguageSyntax`Generate`$builtinFunctions = Get[FileNameJoin[{location, "Resources", "Data", "BuiltinFunctions.wl"}]]
WolframLanguageSyntax`Generate`$constants = Get[FileNameJoin[{location, "Resources", "Data", "Constants.wl"}]]
WolframLanguageSyntax`Generate`$experimentalSymbols = Get[FileNameJoin[{location, "Resources", "Data", "ExperimentalSymbols.wl"}]]
WolframLanguageSyntax`Generate`$obsoleteSymbols = Get[FileNameJoin[{location, "Resources", "Data", "ObsoleteSymbols.wl"}]]
WolframLanguageSyntax`Generate`$systemCharacters = Get[FileNameJoin[{location, "Resources", "Data", "SystemCharacters.wl"}]]
WolframLanguageSyntax`Generate`$systemLongNames = Get[FileNameJoin[{location, "Resources", "Data", "SystemLongNames.wl"}]]
WolframLanguageSyntax`Generate`$undocumentedSymbols = Get[FileNameJoin[{location, "Resources", "Data", "UndocumentedSymbols.wl"}]]


(*
This uses func := func = def idiom and is fast
*)
loadAllFuncs[]


$DefaultConfidenceLevel = 0.75

$CodeActionLiteralSupport = False

$AllowedImplicitTokens = {}

(*
if $BracketMatcher, then load ML4Code` and use ML bracket matching tech
*)
$BracketMatcher = False

$BracketMatcherUseDesignColors = True


$SemanticTokens = False

$HierarchicalDocumentSymbolSupport = False


(*
$BracketMatcherDisplayInsertionText = False
*)

(*
Bracket suggestions from ML4Code can take O(n^2) time in the size of the chunk, so make sure to
have a time limit

Related issues: CODETOOLS-71
*)
$ML4CodeTimeLimit = 0.4


$ExecuteCommandProvider = <|
  "commands" -> {
    (*
    roundtrip_responsiveness_test is an undocumented, debug command
    *)
    "roundtrip_responsiveness_test",
    (*
    ping_pong_responsiveness_test is an undocumented, debug command
    *)
    "ping_pong_responsiveness_test",
    (*
    payload_responsiveness_test is an undocumented, debug command
    *)
    "payload_responsiveness_test"
  }
|>




(*
lint objects may be printed to log files and we do not want to include ANSI control codes
*)
CodeInspector`Format`Private`$UseANSI = False


(*
The counter that is used for creating unique hrefs
*)
$hrefIdCounter = 0



$ErrorCodes = <|
  (*
  Defined by JSON RPC
  *)
  "ParseError" -> -32700,
  "InvalidRequest" -> -32600,
  "MethodNotFound" -> -32601,
  "InvalidParams" -> -32602,
  "InternalError" -> -32603,
  "serverErrorStart" -> -32099,
  "serverErrorEnd" -> -32000,
  "ServerNotInitialized" -> -32002,
  "UnknownErrorCode" -> -32001,

  (*
  Defined by the protocol.
  *)
  "RequestCancelled" -> -32800,
  "ContentModified" -> -32801
|>


$TextDocumentSyncKind = <|
  "None" -> 0,
  "Full" -> 1,
  "Incremental" -> 2
|>

$MessageType = <|
  "Error" -> 1,
  "Warning" -> 2,
  "Info" -> 3,
  "Log" -> 4
|>



$ContentQueue = {}

(*
An assoc of uri -> entry

entry is an assoc of various key/values such as "Text" -> text and "CST" -> cst

*)
$OpenFilesMap = <||>


(*
An assoc of id -> True|False
*)
$CancelMap = <||>



(*
Expands contents and appends to $ContentQueue

Returns Null
*)
expandContentsAndAppendToContentQueue[contentsIn_] :=
  Module[{contents},

    contents = contentsIn;

    If[!MatchQ[contents, {_?AssociationQ ...}],
      log["\n\n"];
      log["Internal assert 1 failed: list of Associations: ", contents];
      log["\n\n"];

      exitHard[]
    ];

    preScanForCancels[contents];

    (*
    Now expand new contents
    *)

    contents = expandContents[contents];

    $ContentQueue = $ContentQueue ~ Join ~ contents;

    If[$Debug2,
      log["appending to $ContentQueue"];
      log["$ContentQueue (up to 20): ", #["method"]& /@ Take[$ContentQueue, UpTo[20]]]
    ];

    
  ]


(*

Use 0.4 seconds, same as default value of spelling squiggly in FE

In[7]:= CurrentValue[$FrontEnd, {SpellingOptions, "AutoSpellCheckDelay"}]

Out[7]= 0.4
*)
$DiagnosticsDelayAfterLastChange = 0.4

$ImplicitTokensDelayAfterLastChange = 3.0

$BracketMatcherDelayAfterLastChange = 4.0



StartServer::notebooks = "LSPServer cannot be started inside of a notebook session."

Options[StartServer] = {
	ConfidenceLevel -> Automatic,
  CommunicationMethod -> "StdIO"
}

(*
setup the REPL to handle traffic from client
*)
StartServer[logDir_String:"", OptionsPattern[]] :=
Catch[
Catch[
Module[{logFile, logFileStream,
  logFileName, logFileCounter, oldLogFiles, now, quantity30days, dateStr, readEvalWriteCycle},

  $kernelStartTime = Now;

  If[$Notebooks,
    (*
    OK to return here without killing the kernel
    This is in a notebook session
    *)
    Message[StartServer::notebooks];
    Throw[$Failed]
  ];

  (*
  This is NOT a notebook session, so it is ok to kill the kernel
  *)

  $ConfidenceLevelOption = OptionValue[ConfidenceLevel];
  $commProcess = OptionValue[CommunicationMethod];


  $MessagePrePrint =.;

  (*
  Ensure that no messages are printed to stdout
  *)
  $Messages = Streams["stderr"];

  (*
  Ensure that no Print output is printed to stdout

  There may have been messages printed from doing Needs["LSPServer`"], and we can't do anything about those
  But they will be detected when doing RunServerDiagnostic[] 
  *)
  $Output = Streams["stderr"];

  $Debug = (logDir != "");

  If[$Debug,

    If[$VersionNumber >= 12.3,
      Quiet[CreateDirectory[logDir], {CreateDirectory::eexist}];
      ,
      Quiet[CreateDirectory[logDir], {CreateDirectory::filex}];
    ];

    (*
    Cleanup existing log files
    *)
    oldLogFiles = FileNames["kernelLog*", logDir];
    now = Now;
    (*
    Was using ":" as a time separator
    But obviously cannot use ":" character in file names on Windows!!
    *)
    dateStr = DateString[now, {"Year", "-", "Month", "-", "Day", "_", "Hour24", "-", "Minute", "-", "Second"}];
    quantity30days = Quantity[30, "Days"];
    Do[
      (*
      Delete oldLogFile if not modified for 30 days
      *)
      If[(now - Information[File[oldLogFile]]["LastModificationDate"]) > quantity30days,
        DeleteFile[oldLogFile]
      ]
      ,
      {oldLogFile, oldLogFiles}
    ];

    logFileName = "kernelLog-" <> dateStr;
    logFile = FileNameJoin[{logDir, logFileName <> ".txt"}];

    logFileCounter = 1;
    While[True,
      If[FileExistsQ[logFile],
        logFile = FileNameJoin[{logDir, logFileName <> "-" <> ToString[logFileCounter] <> ".txt"}];
        logFileCounter++;
        ,
        Break[]
      ]
    ];

    logFileStream = OpenWrite[logFile, CharacterEncoding -> "UTF-8"];

    If[FailureQ[logFileStream],
      
      log["\n\n"];
      log["opening log file failed: ", logFileStream];
      log["\n\n"];
      
      exitHard[]
    ];

    $Messages = $Messages ~Join~ { logFileStream };

    $Output = $Output ~Join~ { logFileStream }
  ];

  (*
  Previously tried setting CharacterEncoding -> "UTF-8", but seems to have no effect

  Maybe because stream is already open and being written to?

  TODO: look into any bug reports about setting CharacterEncoding for $Messages
  *)
  SetOptions[$Messages, PageWidth -> Infinity];

  (*
  There may be messages that we want to see

  TODO: investigate resetting the General::stop counter at the start of each eval loop
  *)
  Off[General::stop];


  log["$CommandLine: ", $CommandLine];
  log["\n\n"];

  log["$commProcess: ", $commProcess];
  log["\n\n"];

  log["$ProcessID: ", $ProcessID];
  log["\n\n"];

  log["$ParentProcessID: ", $ParentProcessID];
  log["\n\n"];

  log["Directory[]: ", Directory[]];
  log["\n\n"];


  log["Starting server... (If this is the last line you see, then StartServer[] may have been called in an unexpected way and the server is hanging.)"];
  log["\n\n"];


  If[$startupMessagesText =!= "",
    log["\n\n"];
    log["There were messages when loading LSPServer` package: ", $startupMessagesText];
    log["\n\n"];
    
    exitHard[]
  ];


  (*
  This is the first use of LSPServer library, so this is where the library is initialized.
  Handle any initialization failures or other errors.
  *)

  $initializedComm = initializeLSPComm[$commProcess];

  If[FailureQ[$initializedComm],
    log["\n\n"];
    (*
    //InputForm to work-around bug 411375
    *)
    log["Initialization failed: ", $initializedComm //InputForm];
    log["\n\n"];
    
    exitHard[]
  ];

  readEvalWriteCycle = readEvalWriteLoop[$commProcess, $initializedComm];

  If[FailureQ[readEvalWriteCycle],
    log["\n\n"];
    log["Read-Eval-Write-Loop failed: ", readEvalWriteCycle];
    log["\n\n"];
    
    exitHard[]
  ];

]],(*Module, 1-arg Catch*)
_,
(
  log["\n\n"];
  log["uncaught Throw: ", #1];
  log["\n\n"];
  
  exitHard[]

  )&
]


preScanForCancels[contents:{_?AssociationQ ...}] :=
  Module[{cancels, params, id},

    cancels = Cases[contents, KeyValuePattern["method" -> "$/cancelRequest"]];

    Scan[
      Function[{content},
        params = content["params"];

        id = params["id"];

        $CancelMap[id] = True
      ], cancels];

    If[$Debug2,
      log["after preScanForCancels"];
      log["$CancelMap: ", $CancelMap]
    ]
  ]


(*
Input: list of Associations
Returns: list of Associations
*)
expandContents[contentsIn_] :=
Module[{contents, lastContents},

  contents = contentsIn;

  If[$Debug2,
    log["before expandContent"]
  ];

  Block[{$PreExpandContentQueue},

    $PreExpandContentQueue = contents;

    lastContents = $PreExpandContentQueue;

    $PreExpandContentQueue = Flatten[MapIndexed[expandContent, $PreExpandContentQueue] /. expandContent[c_, _] :> {c}];

    If[$Debug2,
      log["$PreExpandContentQueue (up to 20): ", #["method"]& /@ Take[$PreExpandContentQueue, UpTo[20]]];
      log["..."]
    ];

    While[$PreExpandContentQueue =!= lastContents,

      If[$Debug2,
        log["expanded (up to 20): ", #["method"]& /@ Take[$PreExpandContentQueue, UpTo[20]]];
        log["..."]
      ];

      lastContents = $PreExpandContentQueue;

      $PreExpandContentQueue = Flatten[MapIndexed[expandContent, $PreExpandContentQueue] /. expandContent[c_, _] :> {c}];

      If[$Debug2,
        log["$PreExpandContentQueue (up to 20): ", #["method"]& /@ Take[$PreExpandContentQueue, UpTo[20]]];
        log["..."]
      ]
    ];

    If[$Debug2,
      log["after expandContent"]
    ];

    contents = $PreExpandContentQueue;
  ];

  If[!MatchQ[contents, {_?AssociationQ ...}],
    log["\n\n"];
    log["Internal assert 2 failed: list of Associations: ", contents];
    log["\n\n"];

    exitHard[]
  ];

  contents
]


ProcessScheduledJobs[] :=
Catch[
Module[{openFilesMapCopy, entryCopy, jobs, res, methods, contents, toRemove, job, toRemoveIndices, contentsToAdd},

  (*
  Do not process any scheduled jobs after shutdown
  *)
  If[$ServerState == "shutdown",
    Throw[Null]
  ];

  openFilesMapCopy = $OpenFilesMap;

  contents = {};
  KeyValueMap[
    Function[{uri, entry},
      jobs = Lookup[entry, "ScheduledJobs", {}];
      toRemoveIndices = {};
      Do[
        job = jobs[[j]];
        res = job[entry];
        {methods, toRemove} = res;

        contentsToAdd = <| "method" -> #, "params" -> <| "textDocument" -> <| "uri" -> uri |> |> |>& /@ methods;

        contents = contents ~Join~ contentsToAdd;

        If[toRemove,
          AppendTo[toRemoveIndices, {j}]
        ]
        ,
        {j, 1, Length[jobs]}
      ];
      If[!empty[toRemoveIndices],
        jobs = Delete[jobs, toRemoveIndices];
        entryCopy = entry;
        entryCopy["ScheduledJobs"] = jobs;
        $OpenFilesMap[uri] = entryCopy
      ]
    ]
    ,
    openFilesMapCopy
  ];

  If[!empty[contents],
  
    contents = expandContents[contents];

    $ContentQueue = $ContentQueue ~Join~ contents;
  ]
]]


(*
input: JSON RPC assoc

returns: a list of JSON RPC assocs
*)
LSPEvaluate[content_(*no Association here, allow everything*)] :=
Catch[
Module[{contents},

  (*
  (*  
  Figuring out what to with UTF-16 surrogates...

  Related bugs: 382744, 397941

  Related issues: https://github.com/microsoft/language-server-protocol/issues/376
  *)

  (*
  Coming in as JSON, so non-ASCII characters are using \uXXXX escaping
  So safe to treat bytes as ASCII
  *)
  str = FromCharacterCode[Normal[bytes], "ASCII"];

  escapes = StringCases[str, "\\u" ~~ ds : (_ ~~ _ ~~ _ ~~ _) :> ds];
  If[escapes != {},
    surrogates = Select[escapes, (
        (* high and low surrogates *)
        16^^d800 <= FromDigits[#, 16] <= 16^^dfff
      )&];
    If[surrogates != {},
      (*
      surrogates have been detected
      *)
      Null
    ]
  ];

  content = ImportString[str, "RawJSON"];
  *)

  Which[
    TrueQ[$ServerState == "shutdown"],
      contents = handleContentAfterShutdown[content]
    ,
    True,
      contents = handleContent[content]
  ];

  If[!MatchQ[contents, {_?AssociationQ ...}],
    log["\n\n"];
    log["Internal assert 3 failed: list of Associations: ", contents];
    log["\n\n"];

    exitHard[]
  ];

  contents
]]



$didOpenMethods = {
  "textDocument/runDiagnostics",
  "textDocument/publishDiagnostics"
}


$didCloseMethods = {
  "textDocument/publishDiagnostics"
}


$didSaveMethods = {}


$didChangeMethods = {}

$didChangeScheduledJobs = {
  Function[{entry}, If[Now - entry["LastChange"] > Quantity[$DiagnosticsDelayAfterLastChange, "Seconds"],
    {{
      "textDocument/runDiagnostics",
      "textDocument/publishDiagnostics"
    }, True},
    {{}, False}]
  ]
}


RegisterDidOpenMethods[meths_] := ($didOpenMethods = Join[$didOpenMethods, meths])

RegisterDidCloseMethods[meths_] := ($didCloseMethods = Join[$didCloseMethods, meths])

RegisterDidSaveMethods[meths_] := ($didSaveMethods = Join[$didSaveMethods, meths])

RegisterDidChangeMethods[meths_] := ($didChangeMethods = Join[$didChangeMethods, meths])

RegisterDidOpenScheduledJobs[jobs_] := ($didOpenScheduledJobs = Join[$didOpenScheduledJobs, jobs])

RegisterDidCloseScheduledJobs[jobs_] := ($didCloseScheduledJobs = Join[$didCloseScheduledJobs, jobs])

RegisterDidSaveScheduledJobs[jobs_] := ($didSaveScheduledJobs = Join[$didSaveScheduledJobs, jobs])

RegisterDidChangeScheduledJobs[jobs_] := ($didChangeScheduledJobs = Join[$didChangeScheduledJobs, jobs])




(*
content: JSON-RPC Association

returns: a list of associations (possibly empty), each association represents JSON-RPC
*)
handleContent[content:KeyValuePattern["method" -> "initialize"]] :=
Module[{id, params, capabilities, textDocument, codeAction, codeActionLiteralSupport, codeActionKind, valueSet,
  codeActionProviderValue, initializationOptions, implicitTokens,
  bracketMatcher, debugBracketMatcher, clientName, semanticTokensProviderValue, semanticTokens, contents,
  documentSymbol, hierarchicalDocumentSymbolSupport},

  If[$Debug2,
    log["initialize: enter"];
    log["content: ", content]
  ];

  id = content["id"];
  params = content["params"];

  If[KeyExistsQ[params, "initializationOptions"],

    initializationOptions = params["initializationOptions"];

    If[$Debug2,
      log["initializationOptions: ", initializationOptions]
    ];

    (*
    initializationOptions may be Null, such as from Jupyter Lab LSP
    *)
    If[AssociationQ[initializationOptions],

      (*

      "confidenceLevel" initialization option is deprecated

      Use ConfidenceLevel option for StartServer

      If[KeyExistsQ[initializationOptions, "confidenceLevel"],
        $ConfidenceLevelInitialization = initializationOptions["confidenceLevel"]
      ];
      *)
      
      If[KeyExistsQ[initializationOptions, "implicitTokens"],
        implicitTokens = initializationOptions["implicitTokens"];

        $AllowedImplicitTokens = implicitTokens
      ];
      If[KeyExistsQ[initializationOptions, "bracketMatcher"],
        bracketMatcher = initializationOptions["bracketMatcher"];

        $BracketMatcher = bracketMatcher
      ];
      If[KeyExistsQ[initializationOptions, "debugBracketMatcher"],
        debugBracketMatcher = initializationOptions["debugBracketMatcher"];

        $DebugBracketMatcher = debugBracketMatcher
      ];
      If[KeyExistsQ[initializationOptions, "semanticTokens"],
        semanticTokens = initializationOptions["semanticTokens"];

        $SemanticTokens = semanticTokens
      ];
    ];
  ];

  (*
  Only use confidenceLevel from initializationOptions if no ConfidenceLevel option was passed to StartServer[]
  *)
  Which[
    NumberQ[$ConfidenceLevelOption],
      $ConfidenceLevel = $ConfidenceLevelOption
    ,
    (* NumberQ[$ConfidenceLevelInitialization],
      $ConfidenceLevel = $ConfidenceLevelInitialization
    , *)
    True,
      $ConfidenceLevel = $DefaultConfidenceLevel
  ];


  If[$Debug2,
    log["$AllowedImplicitTokens: ", $AllowedImplicitTokens];
    log["$BracketMatcher: ", $BracketMatcher];
    log["$DebugBracketMatcher: ", $DebugBracketMatcher];
    log["$ConfidenceLevel: ", $ConfidenceLevel];
    log["$SemanticTokens: ", $SemanticTokens]
  ];


  $ColorProvider = True;

  If[KeyExistsQ[params, "clientName"],
    clientName = params["clientName"];

    (*
    There are multiple problems with Eclipse here:

    Eclipse, or possibly the LSP4E plugin, has strange behavior where 100s or 1000s of documentColor messages
    are sent to the server.

    So we need to disable colorProvider for Eclipse

    Also, Eclipse sends the NON-STANDARD clientName as identification

    VERY ANNOYING!!
    *)
    If[clientName == "Eclipse IDE",
      $ColorProvider = False
    ]
  ];

  If[$Debug2,
    log["$ColorProvider: ", $ColorProvider]
  ];

  
  capabilities = params["capabilities"];
  textDocument = capabilities["textDocument"];
  codeAction = textDocument["codeAction"];

  If[KeyExistsQ[codeAction, "codeActionLiteralSupport"],
    $CodeActionLiteralSupport = True;
    codeActionLiteralSupport = codeAction["codeActionLiteralSupport"];
    codeActionKind = codeActionLiteralSupport["codeActionKind"];
    valueSet = codeActionKind["valueSet"]
  ];

  If[$CodeActionLiteralSupport,
    codeActionProviderValue = <| "codeActionKinds" -> {"quickfix"} |>
    ,
    codeActionProviderValue = True
  ];

  If[$AllowedImplicitTokens != {},

    RegisterDidOpenMethods[{
      "textDocument/runImplicitTokens",
      "textDocument/publishImplicitTokens"
    }];

    RegisterDidCloseMethods[{
      "textDocument/publishImplicitTokens"
    }];

    RegisterDidSaveMethods[{}];

    RegisterDidChangeMethods[{
      "textDocument/clearImplicitTokens",
      "textDocument/publishImplicitTokens"
    }];

    RegisterDidChangeScheduledJobs[{
      Function[{entry}, If[Now - entry["LastChange"] > Quantity[$ImplicitTokensDelayAfterLastChange, "Seconds"],
        {{
          "textDocument/runImplicitTokens",
          "textDocument/publishImplicitTokens"
        }, True},
        {{}, False}]
      ]
    }]
  ];

  If[$BracketMatcher,

    RegisterDidOpenMethods[{
      "textDocument/runBracketMismatches",
      "textDocument/suggestBracketEdits",
      "textDocument/publishBracketMismatches"
    }];

    RegisterDidCloseMethods[{
      "textDocument/publishBracketMismatches"
    }];

    RegisterDidSaveMethods[{}];

    RegisterDidChangeMethods[{
      "textDocument/clearBracketMismatches",
      "textDocument/publishBracketMismatches"
    }];

    RegisterDidChangeScheduledJobs[{
      Function[{entry}, If[Now - entry["LastChange"] > Quantity[$BracketMatcherDelayAfterLastChange, "Seconds"],
        {{
          "textDocument/runBracketMismatches",
          "textDocument/suggestBracketEdits",
          "textDocument/publishBracketMismatches"
        }, True},
        {{}, False}]
      ]
    }];

    $ExecuteCommandProvider =
      Merge[{$ExecuteCommandProvider, <|
        "commands" -> {
          (*
          enable_bracket_matcher_debug_mode is an undocumented, debug command
          *)
          "enable_bracket_matcher_debug_mode",
          (*
          disable_bracket_matcher_debug_mode is an undocumented, debug command
          *)
          "disable_bracket_matcher_debug_mode",
          (*
          enable_bracket_matcher_design_colors is an undocumented, debug command
          *)
          "enable_bracket_matcher_design_colors",
          (*
          disable_bracket_matcher_design_colors is an undocumented, debug command
          *)
          "disable_bracket_matcher_design_colors",
          (*
          nable_bracket_matcher_display_insertion_text is an undocumented, debug command
          *)
          "enable_bracket_matcher_display_insertion_text",
          (*
          disable_bracket_matcher_display_insertion_text is an undocumented, debug command
          *)
          "disable_bracket_matcher_display_insertion_text"
        }
      |>}, Flatten]
  ];

  If[$SemanticTokens,
    If[KeyExistsQ[textDocument, "semanticTokens"],
      semanticTokensProviderValue = <|
        "legend" -> <|
          "tokenTypes" -> Keys[$SemanticTokenTypes],
          "tokenModifiers" -> Keys[$SemanticTokenModifiers]
        |>,
        "range" -> False,
        "full" -> <| "delta" -> False |>
      |>
      ,
      (*
      if client does not advertise semantic token support, then do not respond with any support
      *)
      semanticTokensProviderValue = Null
    ];
    ,
    semanticTokensProviderValue = Null
  ];

  If[KeyExistsQ[textDocument, "documentSymbol"],
    documentSymbol = textDocument["documentSymbol"];
    hierarchicalDocumentSymbolSupport = documentSymbol["hierarchicalDocumentSymbolSupport"];
    $HierarchicalDocumentSymbolSupport = hierarchicalDocumentSymbolSupport
  ];

  $kernelInitializeTime = Now;

  If[$Debug2,
    log["time to intialize: ", $kernelInitializeTime - $kernelStartTime]
  ];

  contents = {<| "jsonrpc" -> "2.0", "id" -> id,
      "result" -> <| "capabilities"-> <| "referencesProvider" -> True,
                                         "textDocumentSync" -> <| "openClose" -> True,
                                                                  "save" -> <| "includeText" -> False |>,
                                                                  "change" -> $TextDocumentSyncKind["Full"]
                                                               |>,
                                         "codeActionProvider" -> codeActionProviderValue,
                                         "colorProvider" -> $ColorProvider,
                                         "hoverProvider" -> True,
                                         "definitionProvider" -> True,
                                         "documentFormattingProvider" -> True,
                                         "documentRangeFormattingProvider" -> True,
                                         "executeCommandProvider" -> $ExecuteCommandProvider,
                                         "documentSymbolProvider" -> True,
                                         "selectionRangeProvider" -> True,
                                         "semanticTokensProvider" -> semanticTokensProviderValue
                                     |>
                 |>
  |>};

  contents
]


handleContent[content:KeyValuePattern["method" -> "initialized"]] :=
  Module[{warningMessages},

    If[$Debug2,
      log["initialized: enter"]
    ];

    (*
    Some simple thing to warm-up
    *)
    CodeParse["1+1"];

    If[$BracketMatcher,

      Block[{$ContextPath}, Needs["ML4Code`"]];
   
      (*
      Some simple thing to warm-up
      *)
      ML4Code`SuggestBracketEdits["f["];
    ];

    warningMessages = ServerDiagnosticWarningMessages[];

    If[$Debug2,
      log["warningMessages: ", warningMessages]
    ];

    <|
      "jsonrpc" -> "2.0",
      "method" -> "window/showMessage",
      "params" ->
        <|
          "type" -> $MessageType["Warning"],
          "message" -> #
        |>
    |>& /@ warningMessages
  ]


handleContent[content:KeyValuePattern["method" -> "shutdown"]] :=
Catch[
Module[{id},

  If[$Debug2,
    log["shutdown: enter"]
  ];

  id = content["id"];

  If[Lookup[$CancelMap, id, False],

    $CancelMap[id] =.;

    If[$Debug2,
      log["$CancelMap: ", $CancelMap]
    ];
    
    Throw[{<| "jsonrpc" -> "2.0", "id" -> id, "result" -> Null |>}]
  ];

  $OpenFilesMap =.;

  $ServerState = "shutdown";

  {<| "jsonrpc" -> "2.0", "id" -> id, "result" -> Null |>}
]]

(*
Unexpected call to exit
*)
handleContent[content:KeyValuePattern["method" -> "exit"]] :=
  Module[{},

    If[$Debug2,
      log["exit: enter"]
    ];

    exitSemiGracefully[]
  ]


handleContent[content:KeyValuePattern["method" -> "$/cancelRequest"]] :=
Catch[
Module[{params, id},
  
  If[$Debug2,
    log["$/cancelRequest: enter"]
  ];

  params = content["params"];

  id = params["id"];

  If[!KeyExistsQ[$CancelMap, id],
    Throw[{}]
  ];

  log["cancel was not handled: ", id];

  $CancelMap[id] =.;

  If[$Debug2,
    log["$CancelMap: ", $CancelMap]
  ];

  {}
]]

(*
$ Notifications and Requests

Notification and requests whose methods start with "$/" are messages which are protocol
implementation dependent and might not be implementable in all clients or servers.
For example if the server implementation uses a single threaded synchronous programming
language then there is little a server can do to react to a "$/cancelRequest" notification.
If a server or client receives notifications starting with "$/" it is free to ignore the
notification.
If a server or client receives a requests starting with "$/" it must error the request with
error code MethodNotFound (e.g. -32601).
*)
handleContent[content:KeyValuePattern["method" -> meth_ /; StringMatchQ[meth, "$/" ~~ __]]] :=
Module[{id},

  If[$Debug2,
    log[meth <> ": enter"]
  ];

  If[KeyExistsQ[content, "id"],
    (*
    has id, so this is a request
    *)
    id = content["id"];
    {<| "jsonrpc" -> "2.0", "id" -> id,
      "error" -> <|
        "code" -> $ErrorCodes["MethodNotFound"],
        "message"->"Method Not Found" |> |>}
    ,
    (*
    does not have id, so this is a notification
    something like: $/setTraceNotification
    $/cancelRequest is handled elsewhere
    just ignore
    *)
    {}
  ]
]



handleContentAfterShutdown[content:KeyValuePattern["method" -> "exit"]] :=
  Module[{},

    If[$Debug2,
      log["exit after shutdown: enter"]
    ];

    exitGracefully[]
  ]

(*
Called if any requests or notifications come in after shutdown
*)
handleContentAfterShutdown[content_?AssociationQ] :=
  Module[{id},

    If[$Debug2,
      log["message after shutdown: enter: ", #["method"]&[content]]
    ];

    If[KeyExistsQ[content, "id"],
      (*
      has id, so this is a request
      *)
      id = content["id"];
      {<| "jsonrpc" -> "2.0", "id" -> id,
        "error" -> <|
          "code" -> $ErrorCodes["InvalidRequest"],
          "message"->"Invalid request" |> |>}
      ,
      (*
      does not have id, so this is a notification
      just ignore
      *)
      {}
    ]
  ]


expandContent[content:KeyValuePattern["method" -> "textDocument/didOpen"], pos_] :=
  Catch[
  Module[{params, doc, uri},

    If[$Debug2,
      log["textDocument/didOpen: enter expand"]
    ];

    params = content["params"];
    doc = params["textDocument"];
    uri = doc["uri"];

    If[isStale[$PreExpandContentQueue[[pos[[1]]+1;;]], uri],
    
      If[$Debug2,
        log["stale"]
      ];

      Throw[{<| "method" -> "textDocument/didOpenFencepost", "params" -> params, "stale" -> True |>}]
    ];

    <| "method" -> #, "params" -> params |>& /@ ({
        "textDocument/didOpenFencepost"
      } ~Join~ $didOpenMethods)
  ]]


handleContent[content:KeyValuePattern["method" -> "textDocument/didOpenFencepost"]] :=
Catch[
Module[{params, doc, uri, text, entry},
  
  If[$Debug2,
    log["textDocument/didOpenFencepost: enter"]
  ];

  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];
  text = doc["text"];

  entry = <|
    "Text" -> text,
    "LastChange" -> Now
  |>;

  $OpenFilesMap[uri] = entry;

  {}
]]


handleContent[content:KeyValuePattern["method" -> "textDocument/concreteParse"]] :=
Catch[
Module[{params, doc, uri, cst, text, entry, fileName, fileFormat},

  If[$Debug2,
    log["textDocument/concreteParse: enter"]
  ];

  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];

  If[isStale[$ContentQueue, uri],
    
    If[$Debug2,
      log["stale"]
    ];

    Throw[{}]
  ];

  entry = $OpenFilesMap[uri];

  cst = Lookup[entry, "CST", Null];

  If[cst =!= Null,
    Throw[{}]
  ];

  text = entry["Text"];

  If[$Debug2,
    log["text: ", stringLineTake[StringTake[ToString[text, InputForm], UpTo[1000]], UpTo[20]]];
    log["...\n"]
  ];
  
  If[$Debug2,
    log["before CodeConcreteParse"]
  ];

  fileName = normalizeURI[uri];

  fileFormat = "Package";
  If[FileExtension[fileName] == "wls",
    fileFormat = "Script"
  ];

  cst = CodeConcreteParse[text, "FileFormat" -> fileFormat];

  If[$Debug2,
    log["after CodeConcreteParse"]
  ];

  If[FailureQ[cst],

    (*
    It is possible that a file is open in an editor, the actual file system contents get deleted,
    but the editor still has a stale window open.
    Focusing on that window could trigger a textDocument/didOpen notification, but the file does not exist!
    TODO: is this a bug in Sublime / LSP package?
    *)
    If[MatchQ[cst, Failure["FindFileFailed", _]],
      Throw[{}]
    ];

    Throw[cst]
  ];

  cst[[1]] = File;

  entry["CST"] = cst;

  (*
  save time if the file has no tabs
  *)
  If[!StringContainsQ[text, "\t"],
    entry["CSTTabs"] = cst
  ];

  $OpenFilesMap[uri] = entry;

  {}
]]


handleContent[content:KeyValuePattern["method" -> "textDocument/concreteTabsParse"]] :=
Catch[
Module[{params, doc, uri, text, entry, cstTabs, fileName, fileFormat},

  If[$Debug2,
    log["textDocument/concreteTabsParse: enter"]
  ];

  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];

  If[isStale[$ContentQueue, uri],
    
    If[$Debug2,
      log["stale"]
    ];

    Throw[{}]
  ];

  entry = $OpenFilesMap[uri];

  cstTabs = Lookup[entry, "CSTTabs", Null];

  If[cstTabs =!= Null,
    Throw[{}]
  ];

  text = entry["Text"];

  (*
  Using "TabWidth" -> 4 here because the notification is rendered down to HTML and tabs need to be expanded in HTML
  FIXME: Must use the tab width from the editor
  *)

  If[$Debug2,
    log["before CodeConcreteParse (TabWidth 4)"]
  ];

  fileName = normalizeURI[uri];

  fileFormat = "Package";
  If[FileExtension[fileName] == "wls",
    fileFormat = "Script"
  ];

  cstTabs = CodeConcreteParse[text, "TabWidth" -> 4, "FileFormat" -> fileFormat];

  If[$Debug2,
    log["after CodeConcreteParse (TabWidth 4)"]
  ];

  If[FailureQ[cstTabs],

    (*
    It is possible that a file is open in an editor, the actual file system contents get deleted,
    but the editor still has a stale window open.
    Focusing on that window could trigger a textDocument/didOpen notification, but the file does not exist!
    TODO: is this a bug in Sublime / LSP package?
    *)
    If[MatchQ[cstTabs, Failure["FindFileFailed", _]],
      Throw[{}]
    ];

    Throw[cstTabs]
  ];

  cstTabs[[1]] = File;

  entry["CSTTabs"] = cstTabs;

  $OpenFilesMap[uri] = entry;

  {}
]]


handleContent[content:KeyValuePattern["method" -> "textDocument/aggregateParse"]] :=
Catch[
Module[{params, doc, uri, cst, text, entry, agg},

  If[$Debug2,
    log["textDocument/aggregateParse: enter"]
  ];

  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];

  If[isStale[$ContentQueue, uri],
    
    If[$Debug2,
      log["stale"]
    ];

    Throw[{}]
  ];

  entry = $OpenFilesMap[uri];

  text = entry["Text"];

  agg = Lookup[entry, "Agg", Null];

  If[agg =!= Null,
    Throw[{}]
  ];

  cst = entry["CST"];
  
  If[$Debug2,
    log["before Aggregate"]
  ];

  agg = CodeParser`Abstract`Aggregate[cst];

  If[$Debug2,
    log["after Aggregate"]
  ];

  entry["Agg"] = agg;

  (*
  save time if the file has no tabs
  *)
  If[!StringContainsQ[text, "\t"],
    entry["AggTabs"] = agg
  ];

  $OpenFilesMap[uri] = entry;

  {}
]]


handleContent[content:KeyValuePattern["method" -> "textDocument/aggregateTabsParse"]] :=
Catch[
Module[{params, doc, uri, entry, cstTabs, aggTabs},

  If[$Debug2,
    log["textDocument/aggregateTabsParse: enter"]
  ];

  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];

  If[isStale[$ContentQueue, uri],
    
    If[$Debug2,
      log["stale"]
    ];

    Throw[{}]
  ];

  entry = $OpenFilesMap[uri];

  aggTabs = Lookup[entry, "AggTabs", Null];

  If[aggTabs =!= Null,
    Throw[{}]
  ];

  cstTabs = entry["CSTTabs"];

  (*
  Using "TabWidth" -> 4 here because the notification is rendered down to HTML and tabs need to be expanded in HTML
  FIXME: Must use the tab width from the editor
  *)

  If[$Debug2,
    log["before Aggregate"]
  ];

  aggTabs = CodeParser`Abstract`Aggregate[cstTabs];

  If[$Debug2,
    log["after Aggregate"]
  ];

  If[FailureQ[aggTabs],
    Throw[aggTabs]
  ];

  entry["AggTabs"] = aggTabs;

  $OpenFilesMap[uri] = entry;

  {}
]]

handleContent[content:KeyValuePattern["method" -> "textDocument/abstractParse"]] :=
Catch[
Module[{params, doc, uri, entry, agg, ast},

  If[$Debug2,
    log["textDocument/abstractParse: enter"]
  ];

  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];

  If[isStale[$ContentQueue, uri],
    
    If[$Debug2,
      log["stale"]
    ];

    Throw[{}]
  ];
  
  entry = $OpenFilesMap[uri];

  ast = Lookup[entry, "AST", Null];

  If[ast =!= Null,
    Throw[{}]
  ];

  agg = entry["Agg"];
  
  If[$Debug2,
    log["before Abstract"]
  ];

  ast = CodeParser`Abstract`Abstract[agg];

  If[$Debug2,
    log["after Abstract"]
  ];

  entry["AST"] = ast;

  $OpenFilesMap[uri] = entry;

  {}
]]



expandContent[content:KeyValuePattern["method" -> "textDocument/didClose"], pos_] :=
  Catch[
  Module[{params, doc, uri},

    If[$Debug2,
      log["textDocument/didClose: enter expand"]
    ];

    params = content["params"];
    doc = params["textDocument"];
    uri = doc["uri"];

    If[isStale[$PreExpandContentQueue[[pos[[1]]+1;;]], uri],
    
      If[$Debug2,
        log["stale"]
      ];

      Throw[{<| "method" -> "textDocument/didCloseFencepost", "params" -> params, "stale" -> True |>}]
    ];

    <| "method" -> #, "params" -> params |>& /@ ({
        "textDocument/didCloseFencepost"
      } ~Join~ $didCloseMethods)
  ]]

handleContent[content:KeyValuePattern["method" -> "textDocument/didCloseFencepost"]] :=
Module[{params, doc, uri},

  If[$Debug2,
    log["textDocument/didCloseFencepost: enter"]
  ];

  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];

  $OpenFilesMap[uri] =.;

  {}
]



expandContent[content:KeyValuePattern["method" -> "textDocument/didSave"], pos_] :=
  Catch[
  Module[{params, doc, uri},

    If[$Debug2,
      log["textDocument/didSave: enter expand"]
    ];

    params = content["params"];
    doc = params["textDocument"];
    uri = doc["uri"];

    If[isStale[$PreExpandContentQueue[[pos[[1]]+1;;]], uri],
    
      If[$Debug2,
        log["stale"]
      ];

      Throw[{<| "method" -> "textDocument/didSaveFencepost", "params" -> params, "stale" -> True |>}]
    ];

    <| "method" -> #, "params" -> params |>& /@ ({
        "textDocument/didSaveFencepost"
      } ~Join~ $didSaveMethods)
  ]]

handleContent[content:KeyValuePattern["method" -> "textDocument/didSaveFencepost"]] :=
  Module[{},

    If[$Debug2,
      log["textDocument/didSaveFencepost: enter"]
    ];

    {}
  ]



expandContent[content:KeyValuePattern["method" -> "textDocument/didChange"], pos_] :=
  Catch[
  Module[{params, doc, uri},

    If[$Debug2,
      log["textDocument/didChange: enter expand"]
    ];

    params = content["params"];
    doc = params["textDocument"];
    uri = doc["uri"];

    If[isStale[$PreExpandContentQueue[[pos[[1]]+1;;]], uri],
    
      If[$Debug2,
        log["stale"]
      ];

      Throw[{<| "method" -> "textDocument/didChangeFencepost", "params" -> params, "stale" -> True |>}]
    ];

    <| "method" -> #, "params" -> params |>& /@ ({
        "textDocument/didChangeFencepost"
      } ~Join~ $didChangeMethods)
  ]]


handleContent[content:KeyValuePattern["method" -> "textDocument/didChangeFencepost"]] :=
Catch[
Module[{params, doc, uri, text, lastChange, entry, changes},
  
  If[$Debug2,
    log["textDocument/didChangeFencepost: enter"]
  ];

  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];
  
  If[Lookup[content, "stale", False] || isStale[$ContentQueue, uri],
    
    If[$Debug2,
      log["stale"]
    ];

    Throw[{}]
  ];
  
  changes = params["contentChanges"];

  (*
  Currently only supporting full text, so always only apply the last change
  *)
  lastChange = changes[[-1]];

  text = lastChange["text"];

  entry = <|
    "Text" -> text,
    "LastChange" -> Now,
    "ScheduledJobs" -> $didChangeScheduledJobs
  |>;

  $OpenFilesMap[uri] = entry;

  {}
]]


exitGracefully[] := (
  log["\n\n"];
  log["KERNEL IS EXITING GRACEFULLY"];
  log["\n\n"];
  shutdownLSPComm[$commProcess, $initializedComm];
  Pause[1];Exit[0]
)

exitSemiGracefully[] := (
  log["Language Server kernel did not shutdown properly."];
  log[""];
  log["This is the command that was used:"];
  log[$CommandLine];
  log[""];
  log["To help diagnose the problem, run this in a notebook:\n" <>
  "Needs[\"LSPServer`\"]\n" <>
  "LSPServer`RunServerDiagnostic[{" <>
    StringJoin[Riffle[("\"" <> # <> "\"")& /@ StringReplace[$CommandLine, "\"" -> "\\\""], ", "]] <>
    "}]"];
  log[""];
  log["Fix any problems then restart and try again."];
  log["\n\n"];
  log["KERNEL IS EXITING SEMI-GRACEFULLY"];
  log["\n\n"];
  shutdownLSPComm[$commProcess, $initializedComm];
  Pause[1];Exit[1]
)

exitHard[] := (
  log["Language Server kernel did not shutdown properly."];
  log[""];
  log["This is the command that was used:"];
  log[$CommandLine];
  log[""];
  log["To help diagnose the problem, run this in a notebook:\n" <>
  "Needs[\"LSPServer`\"]\n" <>
  "LSPServer`RunServerDiagnostic[{" <>
    StringJoin[Riffle[("\"" <> # <> "\"")& /@ StringReplace[$CommandLine, "\"" -> "\\\""], ", "]] <>
    "}]"];
  log[""];
  log["Fix any problems then restart and try again."];
  log["\n\n"];
  log["KERNEL IS EXITING HARD"];
  log["\n\n"];
  shutdownLSPComm[$commProcess, $initializedComm];
  Pause[1];Exit[1]
)


(*
now cleanup Startup Messages handling
*)
Module[{name},

  If[!FailureQ[$startupMessagesFile],

    name = Close[$startupMessagesFile];

    $startupMessagesText = Import[name, "Text"];

    DeleteFile[name];

    $Messages = $oldMessages
  ]
]


End[]

EndPackage[]
