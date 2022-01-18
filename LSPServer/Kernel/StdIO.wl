BeginPackage["LSPServer`StdIO`"]


Begin["`Private`"]

Needs["LSPServer`"]
Needs["LSPServer`Library`"]
Needs["LSPServer`Utils`"]
Needs["CodeParser`Utils`"]

(* ========================================================== *)
(* ================   StdIO functions   ===================== *)
(* ========================================================== *)



(* =================   Initialize   ======================= *)

(*
May return Null or a Failure object
*)
initializeLSPComm["StdIO"] :=
Catch[
Module[{startupError},
  startupError = StartBackgroundReaderThread[];
  If[startupError != 0,
    (*
    For example, on Windows, running WolframKernel.exe from command prompt will give library error 1
    *)
    Throw[Failure["LSPServerNativeLibraryStartupError", <| "StartupError" -> startupError |>]]
  ];
  Null
]]


(* =================   Read Message   ======================= *)

TryQueue["StdIO"] :=
  Catch[
  Module[{bytes,
    queueSize, frontMessageSize,
    content,
    bytessIn, contentsIn},

    (*
    NOTE: when bug 419428 is fixed, then check bugfix and use WithCleanup
    *)
    (*
    BEGIN LOCK REGION
    *)
    LockQueue[];

    queueSize = GetQueueSize[];

    If[queueSize == 0,
      UnlockQueue[];
      Throw[Null]
    ];

    If[$Debug2,
        log["\n\n"];
        log["messages in queue: ", queueSize];
        log["\n\n"]
    ];

    bytessIn = {};
    Do[

      frontMessageSize = GetFrontMessageSize[];
      
      If[frontMessageSize == 0,

        UnlockQueue[];

        log["\n\n"];
        log["FrontMessage size was 0; shutting down"];
        log["\n\n"];

        exitHard[];
      ];

      bytes = PopQueue[frontMessageSize];

      AppendTo[bytessIn, bytes]
      , 
      queueSize
    ];

    UnlockQueue[];
    (*
    END LOCK REGION
    *)

    contentsIn = {};
    Do[
      If[FailureQ[bytesIn],
        log["\n\n"];
        log["invalid bytes from stdin: ", bytesIn];
        log["\n\n"];
        
        exitHard[]
      ];

      If[$Debug2,
        log["C-->S " <> ToString[Length[bytesIn]] <> " bytes"];
        log["C-->S " <> stringLineTake[FromCharacterCode[Normal[Take[bytesIn, UpTo[1000]]]], UpTo[20]]];
        log["...\n"]
      ];

      content = Developer`ReadRawJSONString[ByteArrayToString[bytesIn]];

      AppendTo[contentsIn, content]
      ,
      {bytesIn, bytessIn}
    ];

    bytessIn = {};

    expandContentsAndAppendToContentQueue[contentsIn]

  ]]


handleContent[content:KeyValuePattern["method" -> "stdio/error"]] :=
Module[{err, errStr, ferror},

  err = content["code"];

  Switch[err,
    $LSPServerLibraryError["FREAD_FAILED"],
      Which[
        GetStdInFEOF[] != 0,
          errStr = "fread EOF"
        ,
        (ferror = GetStdInFError[]) != 0,
          errStr = "fread error: " <> ToString[ferror]
        ,
        True,
          errStr = "fread unknown error"
      ]
    ,
    $LSPServerLibraryError["UNEXPECTED_LINEFEED"],
      errStr = "unexpected linefeed"
    ,
    $LSPServerLibraryError["EXPECTED_LINEFEED"],
      errStr = "expected linefeed"
    ,
    $LSPServerLibraryError["UNRECOGNIZED_HEADER"],
      errStr = "unrecognized header"
    ,
    _,
      errStr = "UNKNOWN ERROR: " <> ToString[err]
  ];

  log["\n\n"];
  log["StdIO Error: ", errStr];
  log["\n\n"];

  If[TrueQ[$ServerState == "shutdown"],
    exitSemiGracefully[]
    ,
    exitHard[]
  ]
]


(* ================   Write Message   ======================= *)
(* contents is a list of Associations *)
writeLSPResult["StdIO", sock_, contents_] := writeLSPResult["StdIO", contents]

writeLSPResult["StdIO", contents_] :=
Module[{bytess, res, errStr, ferror},

  Check[
    bytess = StringToByteArray[Developer`WriteRawJSONString[#]]& /@ contents

    ,
    log["\n\n"];
    log["message generated by contents: ", contents];
    log["\n\n"]
    ,
    {Export::jsonstrictencoding}
  ];
  (*
  write out each byte array in bytess
  *)
  Do[

    If[!ByteArrayQ[bytes],

        log["\n\n"];
        log["invalid bytes: ", bytes];
        log["\n\n"];

        exitHard[]
    ];
    (*
    Write the headers
    *)
    Do[
      If[$Debug2,
          log[""];
          log["C<--S  ", line]
      ];

      res = WriteLineToStdOut[line];
      If[res =!= 0,

        Switch[res,
          $LSPServerLibraryError["FWRITE_FAILED"] | $LSPServerLibraryError["FFLUSH_FAILED"],
            Which[
              GetStdOutFEOF[] != 0,
                errStr = "fwrite EOF"
              ,
              (ferror = GetStdOutFError[]) != 0,
                errStr = "fwrite error: " <> ToString[ferror]
                ,
                True,
                  errStr = "fwrite unknown error"
            ]
          ,
          _,
            errStr = "UNKNOWN ERROR: " <> ToString[res]
        ];

        log["\n\n"];
        log["StdOut error: ", errStr];
        log["\n\n"];

        If[TrueQ[$ServerState == "shutdown"],
          exitSemiGracefully[]
          ,
          exitHard[]
          ]
      ]
      ,
      {line, {"Content-Length: " <> ToString[Length[bytes]], ""}}
    ];
    (*
    Write the body
    *)
    If[$Debug2,
      log["C<--S  ", stringLineTake[FromCharacterCode[Normal[Take[bytes, UpTo[1000]]]], UpTo[20]]];
      log["...\n"]
    ];

    res = WriteBytesToStdOut[bytes];
    If[res =!= 0,

      Switch[res,
        $LSPServerLibraryError["FWRITE_FAILED"] | $LSPServerLibraryError["FFLUSH_FAILED"],
          Which[
            GetStdOutFEOF[] != 0,
              errStr = "fwrite EOF"
            ,
            (ferror = GetStdOutFError[]) != 0,
              errStr = "fwrite error: " <> ToString[ferror]
            ,
            True,
              errStr = "fwrite unknown error"
          ]
        ,
        _,
          errStr = "UNKNOWN ERROR: " <> ToString[res]
      ];

      log["\n\n"];
      log["StdOut error: ", errStr];
      log["\n\n"];

      If[TrueQ[$ServerState == "shutdown"],
        exitSemiGracefully[]
        ,
        exitHard[]
      ]
    ]
    ,
    {bytes, bytess} 
  ](*Do bytess*)
]

readEvalWriteLoop["StdIO", sock_]:= 
Module[{content, contents},

  (*
  loop over:
    read content
    evaluate
    write content
  *)

  While[True,

    TryQueue["StdIO"];

    ProcessScheduledJobs[];

    If[empty[$ContentQueue],
      Pause[0.1];
      Continue[]
    ];

    content = $ContentQueue[[1]];
    $ContentQueue = Rest[$ContentQueue];

    If[$Debug2,
      log["taking first from $ContentQueue: ", #["method"]&[content]];
      log["rest of $ContentQueue (up to 20): ", Take[#["method"]& /@ $ContentQueue, UpTo[20]]];
      log["..."]
    ];

    contents = LSPEvaluate[content];

    (* write out evaluated results to the client *)
    writeLSPResult["StdIO", sock, contents];

  ](*While*)
]

(* ============================ ShutDown ============================= *)
shutdownLSPComm["StdIO", _] := Null

End[]

EndPackage[]
