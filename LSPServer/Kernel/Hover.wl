BeginPackage["LSPServer`Hover`"]

Begin["`Private`"]

Needs["LSPServer`"]
Needs["LSPServer`ReplacePUA`"]
Needs["LSPServer`Utils`"]
Needs["CodeParser`"]
Needs["CodeParser`Utils`"]


handleContent[content:KeyValuePattern["method" -> "textDocument/hover"]] :=
Catch[
Module[{id, params, doc, uri, position, entry, text, textLines, strs, positionLine, positionColumn, pre, cstTabs, syms, toks, nums},

  id = content["id"];
  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];
  position = params["position"];

  entry = $OpenFilesMap[uri];

  positionLine = position["line"];
  positionColumn = position["character"];
  
  (*
  Convert from 0-based to 1-based
  *)
  positionLine++;
  positionColumn++;

  text = entry[[1]];
  cstTabs = entry[[3]];

  If[cstTabs === Null,
    (*
    Using "TabWidth" -> 4 here because the notification is rendered down to HTML and tabs need to be expanded in HTML
    FIXME: Must use the tab width from the editor
    *)
    cstTabs = CodeConcreteParse[text, "TabWidth" -> 4];
    
    $OpenFilesMap[[Key[uri], 3]] = cstTabs;
  ];

  If[StringContainsQ[text, "\t"],
    (*
    Adjust the hover position to accommodate tab stops
    FIXME: Must use the tab width from the editor
    *)
    textLines = StringSplit[text, {"\r\n", "\n", "\r"}, All];
    pre = StringTake[textLines[[positionLine]], positionColumn-1];
    positionColumn = 1;
    Scan[(If[# == "\t", positionColumn = (4 * Quotient[positionColumn, 4] + 1) + 4, positionColumn++])&, Characters[pre]];
  ];

  
  toks = Cases[cstTabs,
    LeafNode[_, _,
      KeyValuePattern[Source -> src_ /; SourceMemberQ[src, {positionLine, positionColumn}]]], Infinity];

  strs = Cases[toks, LeafNode[String, _, _], Infinity];

  syms = Cases[toks, LeafNode[Symbol, _, _], Infinity];

  nums = Cases[toks, LeafNode[Integer | Real | Rational, _, _], Infinity];

  Which[
    strs != {},
      handleStrings[id, strs]
    ,
    syms != {},
      handleSymbols[id, syms]
    ,
    nums != {},
      handleNumbers[id, nums]
    ,
    True,
      {<|"jsonrpc" -> "2.0", "id" -> id, "result" -> Null |>}
  ]
]]


(*
For strings that contain \[] or \: notation, display the decoded string
*)
handleStrings[id_, strsIn_] :=
Catch[
Module[{lines, lineMap, originalLineNumber, line,
  originalColumn, rules, char, decoded, rule, positionLine, segment, index, result, segments,
  originalColumnCount, strs},

  (*
  Find strings with multi-SourceCharacter WLCharacters
  *)
  strs = Cases[strsIn, LeafNode[String, str_ /; containsUnicodeCharacterQ[str], _], Infinity];

  lineMap = <||>;

  Function[{str},

    {originalLineNumber, originalColumn} = str[[3, Key[Source], 1]];

    segments = StringSplit[str[[2]], {"\r\n", "\n", "\r"}, All];

    If[Length[segments] == 1,

      segment = segments[[1]];

      rules = {};
      
      decoded = convertSegment[segment];

      (*
      Handle tab stops
      FIXME: Must use the tab width from the editor
      *)
      originalColumnCount = 1;
      Scan[(
        If[# == "\t", originalColumnCount = (4 * Quotient[originalColumnCount, 4] + 1) + 4, originalColumnCount++];)&
        ,
        Characters[decoded]
      ];

      If[!FailureQ[decoded],
        index = 1;
        Function[{char},
          Switch[char,
            "\t",
              index = (4 * Quotient[index, 4] + 1) + 4
            ,
            " ",
              index++
            ,
            _,
              rule = index -> char;
              AppendTo[rules, rule];
              index++
          ]
        ] /@ Characters[decoded]
      ];

      If[rules != {},

        line = <| "line" -> originalLineNumber, "characters" -> ReplacePart[Table[" ", {originalColumnCount + 1}], rules]|>;

        If[KeyExistsQ[lineMap, line["line"]],
          lineMap[line["line"]] = merge[lineMap[line["line"]], line]
          ,
          lineMap[line["line"]] = line
        ];
      ]

      ,
      (* Length[segments] > 1 *)

      MapIndexed[Function[{segment, segmentIndex},

        rules = {};
        Which[
          (positionLine == (originalLineNumber + segmentIndex[[1]] - 1)) && containsUnicodeCharacterQ[segment] && segmentIndex == {1},
            decoded = convertStartingSegment[segment];
            If[!FailureQ[decoded],

              (*
              Handle tab stops
              FIXME: Must use the tab width from the editor
              *)
              originalColumnCount = 1;
              Scan[(
                If[# == "\t", originalColumnCount = (4 * Quotient[originalColumnCount, 4] + 1) + 4, originalColumnCount++];)&
                ,
                Characters[decoded]
              ];

              index = 1;
              Function[{char},
                Switch[char,
                  "\t",
                    index = (4 * Quotient[index, 4] + 1) + 4
                  ,
                  " ",
                    index++
                  ,
                  _,
                    rule = index -> char;
                    AppendTo[rules, rule];
                    index++
                ];
              ] /@ Characters[decoded]
            ];
          ,
          (positionLine == (originalLineNumber + segmentIndex[[1]] - 1)) && containsUnicodeCharacterQ[segment] && segmentIndex == {Length[segments]},
            decoded = convertEndingSegment[segment];
            If[!FailureQ[decoded],

              (*
              Handle tab stops
              FIXME: Must use the tab width from the editor
              *)
              originalColumnCount = 1;
              Scan[(
                If[# == "\t", originalColumnCount = (4 * Quotient[originalColumnCount, 4] + 1) + 4, originalColumnCount++];)&
                ,
                Characters[decoded]
              ];

              index = 1;
              Function[{char},
                Switch[char,
                  "\t",
                    index = (4 * Quotient[index, 4] + 1) + 4
                  ,
                  " ",
                    index++
                  ,
                  _,
                    rule = index -> char;
                    AppendTo[rules, rule];
                    index++
                ];
              ] /@ Characters[decoded]
            ];
          ,
          (positionLine == (originalLineNumber + segmentIndex[[1]] - 1)) && containsUnicodeCharacterQ[segment],
            decoded = convertMiddleSegment[segment];
            If[!FailureQ[decoded],

              (*
              Handle tab stops
              FIXME: Must use the tab width from the editor
              *)
              originalColumnCount = 1;
              Scan[(
                If[# == "\t", originalColumnCount = (4 * Quotient[originalColumnCount, 4] + 1) + 4, originalColumnCount++];)&
                ,
                Characters[decoded]
              ];

              index = 1;
              Function[{char},
                Switch[char,
                  "\t",
                    index = (4 * Quotient[index, 4] + 1) + 4
                  ,
                  " ",
                    index++
                  ,
                  _,
                    rule = index -> char;
                    AppendTo[rules, rule];
                    index++
                ];
              ] /@ Characters[decoded]
            ];
        ];

        If[rules != {},

          line = <| "line" -> originalLineNumber + segmentIndex[[1]] - 1, "characters" -> ReplacePart[Table[" ", {originalColumnCount + 1}], rules]|>;

          If[KeyExistsQ[lineMap, line["line"]],
            lineMap[line["line"]] = merge[lineMap[line["line"]], line]
            ,
            lineMap[line["line"]] = line
          ];
        ]

      ], segments]

    ];

  ] /@ strs;

  lines = Values[lineMap];

  lines = escapeMarkdown[replacePUA[StringJoin[#["characters"]]]]& /@ lines;

  Which[
    Length[lines] == 0,
      result = Null
    ,
    Length[lines] == 1,
      result = <| "contents" -> <| "kind" -> "markdown", "value" -> lines[[1]] |> |>
    ,
    True,
      result = <| "contents" -> "BAD!!!" |>
  ];

  {<|"jsonrpc" -> "2.0", "id" -> id, "result" -> result |>}
]]


(*
For symbols, display their usage message
*)
handleSymbols[id_, symsIn_] :=
Catch[
Module[{lines, line, result, syms, usage, a1},

  syms = symsIn;

  syms = #["String"]& /@ syms;

  lines = Function[{sym},

    usage = ToExpression[sym <> "::usage"];

    If[StringQ[usage],

      a1 = reassembleEmbeddedLinearSyntax[CodeTokenize[usage]] /. {
        LeafNode[Token`Newline, _, _] -> "\n\n",
        LeafNode[Token`LinearSyntax`Bang, _, _] -> "",
        LeafNode[Token`LinearSyntaxBlob, s_, _] :> parseLinearSyntaxBlob[s],
        LeafNode[String, s_, _] :> parseString[s],
        LeafNode[_, s_, _] :> escapeMarkdown[replacePUA[s]],
        ErrorNode[_, s_, _] :> escapeMarkdown[replacePUA[s]]
      };
      line = StringJoin[a1];

      If[StringQ[line],
        line
        ,
        "INVALID"
      ]
      ,
      Nothing
    ]

  ] /@ syms;

  Which[
    Length[lines] == 0,
      result = Null
    ,
    Length[lines] == 1,
      result = <| "contents" -> <| "kind" -> "markdown", "value" -> lines[[1]] |> |>
    ,
    True,
      result = <| "contents" -> "BAD!!!" |>
  ];

  {<|"jsonrpc" -> "2.0", "id" -> id, "result" -> result |>}
]]


(*
For numbers with ^^, display their decimal value
*)
handleNumbers[id_, numsIn_] :=
Catch[
Module[{lines, result, nums, dec},

  nums = numsIn;

  nums = #["String"]& /@ nums;

  nums = Cases[nums, s_ /; StringContainsQ[s, "^^"]];

  lines = Function[{num},

    dec = ToExpression[num];

    dec = ToString[dec];

    dec

  ] /@ nums;

  Which[
    Length[lines] == 0,
      result = Null
    ,
    Length[lines] == 1,
      result = <| "contents" -> <| "kind" -> "markdown", "value" -> lines[[1]] |> |>
    ,
    True,
      result = <| "contents" -> "BAD!!!" |>
  ];

  {<|"jsonrpc" -> "2.0", "id" -> id, "result" -> result |>}
]]


endsWithOddBackslashesQ[str_String] := 
  StringMatchQ[str, RegularExpression[".*(?<!\\\\)\\\\(\\\\\\\\)*"]]

convertSegment[segment_String /; StringMatchQ[segment, "\"" ~~ ___ ~~ "\""]] :=
  Quiet[Check[ToExpression[segment], $Failed]]

(*
Something from MessageName ::
*)
convertSegment[segment_String] :=
  Quiet[Check[ToExpression["\"" <> segment <> "\""], $Failed]]

convertStartingSegment[segment_] :=
  Quiet[Check[ToExpression[segment <> If[endsWithOddBackslashesQ[segment], "\\\"", "\""]], $Failed]]

convertMiddleSegment[segment_] :=
  Quiet[Check[ToExpression["\"" <> segment <> If[endsWithOddBackslashesQ[segment], "\\\"", "\""]], $Failed]]

convertEndingSegment[segment_] :=
  Quiet[Check[ToExpression["\"" <> segment], $Failed]]



containsUnicodeCharacterQ[str_String] :=
  (*
  Fast test of single backslash before more complicated test
  *)
  StringContainsQ[str, "\\"] &&
  StringContainsQ[str, RegularExpression[
        "(?<!\\\\)\\\\(?:\\\\\\\\)*(?# odd number of leading backslashes)(?:\
(?:\\[[a-zA-Z0-9]+\\])|(?# \\[Alpha] long name)\
(?::[0-9a-fA-F]{4})|(?# \\:xxxx hex)\
(?:\\.[0-9a-fA-F]{2})|(?# \\.xx hex)\
(?:[0-7]{3})|(?# \\xxx octal)\
(?:\\|[0-9a-fA-F]{6})(?# \\|xxxxxx hex)\
)"]]







parseLinearSyntaxBlob[s_] :=
  Block[{$Context = "LSPServer`Hover`Private`"},
    interpretBox[Quiet[ToExpression[s]]]
  ]

parseString[s_] :=
  Module[{a1, unquoted, hasStartingQuote, hasEndingQuote},

    (*
    The string may be reassembled and there may have been an error in the linear syntax,
    meaning tha there is no trailing quote
    *)
    hasStartingQuote = StringMatchQ[s, "\"" ~~ ___];
    hasEndingQuote = StringMatchQ[s, ___ ~~ "\""];
    unquoted = StringReplace[s, (StartOfString ~~ "\"") | ("\"" ~~ EndOfString) -> ""];

    a1 = reassembleEmbeddedLinearSyntax[CodeTokenize[unquoted]] /. {
      LeafNode[Token`LinearSyntax`Bang, _, _] -> "",
      LeafNode[Token`LinearSyntaxBlob, s1_, _] :> parseLinearSyntaxBlob[s1],
      LeafNode[String, s1_, _] :> parseString[s1],
      LeafNode[_, s1_, _] :> escapeMarkdown[replacePUA[s1]],
      ErrorNode[_, s1_, _] :> escapeMarkdown[replacePUA[s1]]
    };
    {If[hasStartingQuote, "\"", ""], a1, If[hasEndingQuote, "\"", ""]}
  ]


interpretBox::unhandled = "unhandled: `1`"

interpretBox::unhandledSeq = "unhandled: `1`\n`2`"

interpretBox::unhandled2 = "FIXME: unhandled: `1`"

interpretBox[RowBox[children_]] :=
  interpretBox /@ children

(*
HACK: BeginPackage::usage has typos
*)
(* interpretBox[StyleBox[a_, TR]] :=
  interpretBox[a] *)

interpretBox[StyleBox[a_, "TI", ___Rule]] :=
  {"*", interpretBox[a], "*"}

interpretBox[StyleBox[a_, _String, ___Rule]] :=
  interpretBox[a]

interpretBox[StyleBox[a_, ___Rule]] :=
  interpretBox[a]

interpretBox[StyleBox[___]] := (
  Message[interpretBox::unhandled, "StyleBox with weird args"];
  "\[UnknownGlyph]"
)

interpretBox[SubscriptBox[a_, b_]] :=
  interpretBox /@ {a, "_", b}

interpretBox[SuperscriptBox[a_, b_, ___Rule]] :=
  interpretBox /@ {a, "^", b}

interpretBox[SubsuperscriptBox[a_, b_, c_]] :=
  interpretBox /@ {a, "_", b, "^", c}

interpretBox[FractionBox[a_, b_]] :=
  interpretBox /@ {a, "/", b}

interpretBox[TagBox[a_, _, ___Rule]] :=
  interpretBox[a]

interpretBox[FormBox[a_, _]] :=
  interpretBox[a]

interpretBox[TooltipBox[a_, _]] :=
  interpretBox[a]

interpretBox[UnderscriptBox[a_, b_, ___Rule]] :=
  interpretBox /@ {a, "+", b}

interpretBox[OverscriptBox[a_, b_]] :=
  interpretBox /@ {a, "&", b}

interpretBox[UnderoverscriptBox[a_, b_, c_, ___Rule]] :=
  interpretBox /@ {a, "+", b, "%", c}

interpretBox[GridBox[_, ___Rule]] := (
  Message[interpretBox::unhandled, "GridBox"];
  "\[UnknownGlyph]"
)

interpretBox[CheckboxBox[_]] := (
  Message[interpretBox::unhandled, "CheckboxBox"];
  "\[UnknownGlyph]"
)

interpretBox[CheckboxBox[_, _]] := (
  Message[interpretBox::unhandled, "CheckboxBox"];
  "\[UnknownGlyph]"
)

interpretBox[TemplateBox[_, _]] := (
  Message[interpretBox::unhandled, "TemplateBox"];
  "\[UnknownGlyph]"
)

interpretBox[SqrtBox[a_]] :=
  interpretBox /@ {"@", a}

interpretBox[OpenerBox[_]] := (
  Message[interpretBox::unhandled, "OpenerBox"];
  "\[UnknownGlyph]"
)

interpretBox[RadioButtonBox[_, _]] := (
  Message[interpretBox::unhandled, "RadioButtonBox"];
  "\[UnknownGlyph]"
)

interpretBox[RadicalBox[a_, b_]] :=
  interpretBox /@ {"@", a, "%", b}

interpretBox[s_String /; StringMatchQ[s, WhitespaceCharacter... ~~ "\"" ~~ __ ~~ "\"" ~~ WhitespaceCharacter...]] :=
  parseString[s]

(*
Sanity check that the box that starts with a letter is actually a single word or sequence of words
*)
interpretBox[s_String /; StringStartsQ[s, LetterCharacter | "$"] &&
  !StringMatchQ[s, (WordCharacter | "$" | " " | "`" | "_" | "/" | "\[FilledRightTriangle]") ...]] := (
  Message[interpretBox::unhandledSeq, "letter sequence that probably should be a RowBox", s];
  "\[UnknownGlyph]"
)

interpretBox[s_String] :=
  escapeMarkdown[replacePUA[s]]

interpretBox[$Failed] := (
  Message[interpretBox::unhandled, $Failed];
  "\[UnknownGlyph]"
)

interpretBox[s_Symbol] := (
  (*
  This is way too common to ever fix properly, so concede and convert to string
  *)
  (* Message[interpretBox::unhandled, Symbol];
  "\[UnknownGlyph]" *)
  ToString[s]
)

(*
HACK: BeginPackage::usage has typos
*)
interpretBox[i_Integer] := (
  Message[interpretBox::unhandled, Integer];
  "\[UnknownGlyph]"
)

(*
HACK: Riffle::usage has a Cell expression
*)
interpretBox[Cell[BoxData[a_], _String, ___Rule]] := (
  Message[interpretBox::unhandled, Cell];
  "\[UnknownGlyph]"
)

interpretBox[Cell[TextData[a_], _String, ___Rule]] := (
  Message[interpretBox::unhandled, Cell];
  "\[UnknownGlyph]"
)

(*
HACK: RandomImage::usage has a typos (missing comma) and creates this expression:
("")^2 (", ")^2 type
*)
interpretBox[_Times] := (
  Message[interpretBox::unhandled, "strange Times (probably missing a comma)"];
  "\[UnknownGlyph]"
)

(*
HACK: NeuralFunctions`Private`MaskAudio::usage has weird typos
*)
interpretBox[_PatternTest] := (
  Message[interpretBox::unhandled, "strange PatternTest"];
  "\[UnknownGlyph]"
)

interpretBox[b_] := (
  Message[interpretBox::unhandled2, b];
  "\[UnknownGlyph]"
)


escapeMarkdown[s_String] :=
  StringReplace[s, {
    (*
    There is some bug in VSCode where it seems that the mere presence of backticks prevents other characters from being considered as escaped

    For example, look at BeginPackage usage message in VSCode
    *)
    "`" -> "\\`",
    "*" -> "\\*",
    "<" -> "&lt;",
    ">" -> "&gt;",
    "&" -> "&amp;",
    "\\" -> "\\\\",
    "_" -> "\\_",
    "{" -> "\\{",
    "}" -> "\\}",
    "[" -> "\\[",
    "]" -> "\\]",
    "(" -> "\\(",
    ")" -> "\\)",
    "#" -> "\\#",
    "+" -> "\\+",
    "-" -> "\\-",
    "." -> "\\.",
    "!" -> "\\!"
  }]



(*
Fix the terrible, terrible design mistake that prevents linear syntax embedded in strings from round-tripping
*)
reassembleEmbeddedLinearSyntax[toks_] :=
  Module[{embeddedLinearSyntax, openerPoss, closerPoss},

    openerPoss = Position[toks, LeafNode[String, s_ /; StringCount[s, "\("] == 1 && StringCount[s, "\)"] == 0, _]];

    closerPoss = Position[toks,
      LeafNode[String, s_ /; StringCount[s, "\("] == 0 && StringCount[s, "\)"] == 1, _] |
        ErrorNode[Token`Error`UnterminatedString, s_ /; StringCount[s, "\("] == 0 && StringCount[s, "\)"] == 1, _]];

    Fold[
      Function[{toks1, span},
        embeddedLinearSyntax = LeafNode[String, StringJoin[#[[2]] & /@ Take[toks1, {span[[1, 1]], span[[2, 1]]}]], <||>];
        ReplacePart[Drop[toks1, {span[[1, 1]] + 1, span[[2, 1]]}], span[[1]] -> embeddedLinearSyntax]]
      ,
      toks
      ,
      Transpose[{openerPoss, closerPoss}] //Reverse
    ]
  ]


End[]

EndPackage[]
