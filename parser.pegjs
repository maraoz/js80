{
  var _ = require('underscore');
  var macro = null;
  var repeat = [];
  var astif = [];
}

Start
  = l:Lines __ LineTerminator* { return l; }

Lines
  = __ head:ProgLine? tail:(__ (LineTerminator/"\\")+ __ ProgLine?)* __ {
    tail = _.map(tail, function(i) { return i[3]; });
    return _.flatten([head, tail]);
  }

ProgLine
  = l:Line {
    if(astif.length && !_.isUndefined(_.last(astif).elseBody)) { _.last(astif).elseBody.push(l); return []; }
    if(astif.length)  { _.last(astif).thenBody.push(l); return []; }
    if(repeat.length) { _.last(repeat).body.push(l); return []; }
    if(macro)         { macro.body.push(l); return []; }
    return l;
  }

Line
  = l:Identifier _ "equ"i _ e:Expr { return {equ:{label:l, value:e}, line:line}; }
  / l:Label _ i:Inst               { return [{label:l, line:line}, i] }
  / l:Label                        { return {label:l, line:line}; }
  / i:Inst                         { return _.isEmpty(i) ? i :_.extend(i, {line:line}); }

Label
  = l:Identifier ":" { return l; }

Inst
  = "."? s:SpecialInst                    { return s; }
  / m:"@@"? asm:Identifier _ args:InstArgs?       { return {asm:{inst:asm, args:args, execmacro:_.isEmpty(m)}}; }

SpecialInst
  = "org"i _ n:Expr                                      { return {org:n}; }
  / "map"i _ n:Expr                                      { return {map:n}; }
  / ("ds"i/"defs"i) _ n:Expr _ "," _ v:Expr              { return {ds:{len:n,value:v}}; }
  / ("ds"i/"defs"i) _ n:Expr                             { return {ds:{len:n,value:{num:0}}}; }
  / ("dw"i/"defw"i) _ head:Expr tail:(_ "," _ Expr)*     { return {dw:[head].concat(_.map(tail, function(i) { return i[3]; }))}; }
  / ("db"i/"defb"i) _ head:DbExpr tail:(_ "," _ DbExpr)* { return {db:[head].concat(_.map(tail, function(i) { return i[3]; }))}; }
  / "module"i _ i:Identifier                             { return {module:i}; }
  / "endmodule"i                                         { return {endmodule:true}; }
  / "include"i _ s:String                                { return {include:s}; }
  / "incbin"i _ s:String _ "," _ k:Expr _ "," _ l:Expr   { return {incbin:{file:s, skip:k, len:l}}; }
  / "incbin"i _ s:String _ "," _ k:Expr                  { return {incbin:{file:s, skip:k}}; }
  / "incbin"i _ s:String                                 { return {incbin:{file:s}}; }
  / "macro"i _ i:Identifier _ a:MacroArgs?               { if(macro) { throw new Error('Forbidden macro declaration'); } macro = {id:i, args:a, body:[]}; return {}; }
  / "endmacro"i                                          { var m = macro; macro = null; return {macro:m}; }
  / ("repeat"i/"rept"i) _ n:Expr                         { repeat.push({count:n, body:[]}); return {}; }
  / ("endrepeat"i/"endr"i)                               { var r = repeat.pop(); return {repeat:r}; }
  / "ifdef"i _ i:Identifier                              { astif.push({defined:i, thenBody:[]}); return {}; }
  / "ifndef"i _ i:Identifier                             { astif.push({undefined:i, thenBody:[]}); return {}; }
  / "if"i _ e:Expr                                       { astif.push({expr:e, thenBody:[]}); return {}; }
  / "else"i                                              { _.last(astif).elseBody = []; return {}; }
  / "endif"i                                             { var i = astif.pop(); return {if:i}; }
  / "rotate"i _ n:Expr                                   { return {rotate:n}; }
  / "defpage"i _ p:PageArg _ "," _ o:Expr _ "," _ s:Expr { return {defpage:{index:p, origin:o, size:s}}; }
  / "page"i _ p:PageArg                                  { return {page:p}; }
  / "echo"i _ head:Expr tail:(_ "," _ Expr)*             { return {echo:[head].concat(_.map(tail, function(i) { return i[3]; }))}; }

PageArg
  = s:Expr _ ".." _ e:Expr      { return {start:s, end:e}; }
  / e:Expr                      { return e };

DbExpr
  = Expr
  / s:String { return {str:s}; }

InstArgs
  = head:Expr tail:(_ "," _ Expr)* { return [head].concat(_.map(tail, function(i) { return i[3]; })); }

MacroArgs
  = head:MacroArg tail:(_ "," _ MacroArg)* { return [head].concat(_.map(tail, function(i) { return i[3]; })); }

MacroArg
  = "1" _ ".." _ "*" __         { return {rest:true}; }
  / i:Identifier _ ":" _ e:Expr { return {id:i, default:e}; }
  / i:Identifier                { return {id:i}; }

//
// Expr
//
Expr
  = e:ExprLogic  { return e; }
  / e:ExprChar   { return {chr:e}; }
  / e:String     { return {str:e}; }

ExprLogic
  = left:ExprCmp _ "^" _ right:ExprLogic { return {unary:"^", args:[left, right]}; }
  / left:ExprCmp _ "|" _ right:ExprLogic { return {unary:"|", args:[left, right]}; }
  / left:ExprCmp _ "&" _ right:ExprLogic { return {unary:"&", args:[left, right]}; }
  / ExprCmp

ExprCmp
  = left:ExprAdd _ "==" _ right:ExprAdd { return {eq: {left:left, right:right}}; }
  / left:ExprAdd _ "!=" _ right:ExprAdd { return {neq:{left:left, right:right}}; }
  / left:ExprAdd _ "<=" _ right:ExprAdd { return {le: {left:left, right:right}}; }
  / left:ExprAdd _ ">=" _ right:ExprAdd { return {ge: {left:left, right:right}}; }
  / left:ExprAdd _ "<"  _ right:ExprAdd { return {lt: {left:left, right:right}}; }
  / left:ExprAdd _ ">"  _ right:ExprAdd { return {gt: {left:left, right:right}}; }
  / ExprAdd

ExprAdd
  = left:ExprMul _ right:([+-] ExprMul)+ {
    var n=[left].concat(_.map(right, function(i) {
      if(i[0]==='-') {
       return {neg:i[1]};
      } else {
       return i[1];
      }
    }));
    return {unary:"+", args:n};
  }
  / ExprMul

ExprMul
  = left:ExprShift _ "*" _ right:ExprMul { return {unary:"*", args:[left, right]}; }
  / left:ExprShift _ "/" _ right:ExprMul { return {unary:"/", args:[left, right]}; }
  / ExprShift

ExprShift
  = left:ExprPrimary _ "<<" _ right:ExprShift { return {unary:"<<", args:[left, right]}; }
  / left:ExprPrimary _ ">>" _ right:ExprShift { return {unary:">>", args:[left, right]}; }
  / ExprPrimary

ExprPrimary
  = "-" e:ExprPrimary { return {neg:e}; }
  / "@" _ e:Expr      { return {arg:e}; }
  / "#" _ e:Expr      { return {getMap:e}; }
  / num:Number        { return {num:num}; }
  / id:Identifier     { return {id:id}; }
  / "$"               { return {id:'__here__'}; }
  / "(" e:ExprAdd ")" { return {paren:e}; }

Number
  = text:[0-9]+ "h"              { return parseInt(text.join(""), 16); }
  / ("0x"/"$") text:[0-9a-fA-F]+ { return parseInt(text.join(""), 16); }
  / "0b" text:[0-1]+             { return parseInt(text.join(""), 2); }
  / text:[0-1]+ "b"              { return parseInt(text.join(""), 2); }
  / text:[0-9]+                  { return parseInt(text.join("")); }

String
  = '"' text:(!'"' .)* '"' { return _.map(text, function(i) { return i[1]; }).join(""); }

ExprChar
  = "'" t:(!"'" .) "'" { return t[1]; }

Identifier
  = p:"."? s:[a-zA-Z_0-9\.]+ { return (p||'') + s.join(''); }

//
// chars
//
Whitespace
  = [\t\v\f \u00A0\uFEFF]

LineTerminator
  = [\n\r\u2028\u2029]

EOF
  = !.

//
// whitespace
//
_
  = (Whitespace / CommentNoLineTerminator)*

__
  = (Whitespace / Comment)*

//
// comments
//
Comment
  = SingleLineComment
  / SingleLineComment2
  / MultiLineComment

SingleLineComment
  = "//" (!LineTerminator .)*

SingleLineComment2
  = ";" (!LineTerminator .)*

MultiLineComment
  = "/*" (!"*/" .)* "*/"

CommentNoLineTerminator
  = SingleLineComment
  / MultiLineCommentNoLineTerminator

MultiLineCommentNoLineTerminator
  = "/*" (!("*/" / LineTerminator) .)* "*/"
