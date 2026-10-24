// Tokenizes one long line, as in a minified bundle, at several lengths.
// Each line repeats a snippet a whole number of times, so every length
// ends the same way: some JavaScript patterns look ahead to the line end.
//   dart run benchmark/long_line.dart [lengths...]
import 'package:syntax_core/langs/javascript.dart';
import 'package:syntax_core/langs/json.dart';
import 'package:syntax_core/syntax.dart';

// Minified JavaScript: functions, arrows, classes, template and regex
// literals, object literals and numbers.
const _js =
    r'var e=function(t,n){return t+n},r=(t,n=0)=>{if(t>n)return t*2;'
    r'for(let i=0;i<n;i++)t+=i;return t},o={name:"Alice",age:30,'
    r"tags:['a','b'],nested:{x:1.5e3,y:0x1F}};class s extends Object"
    r'{constructor(t){super(),this.t=t}get v(){return`v=${this.t}!`}'
    r'static of(t){return new s(t)}}const a=/^[a-z]+\d*$/gi.test("ab12"),'
    r'u=async t=>await fetch(`/api/${t}`).then(n=>n.json());';

// Minified JSON: objects, arrays, strings with escapes, numbers, literals.
const _json =
    r'{"id":12345,"name":"widget \"pro\"","tags":["a","b","c"],'
    r'"price":19.99,"active":true,"meta":null,"dims":{"w":1.5e2,"h":-3}},';

String _line(String unit, int length) =>
    unit * (length / unit.length).round().clamp(1, length);

void main(List<String> args) {
  final lengths = args.isEmpty
      ? const [1000, 10000, 30000, 100000]
      : [for (final a in args) int.parse(a)];
  final highlighter = Highlighter(
    languages: [javascriptLanguage, jsonLanguage],
    maxLineLength: 0,
  );
  for (final (language, unit) in [('javascript', _js), ('json', _json)]) {
    final grammar = highlighter.grammar(language);
    grammar.tokenizeLine(_line(unit, 2000)); // compile and warm up
    for (final length in lengths) {
      final line = _line(unit, length);
      final runs = length <= 10000 ? 5 : 1;
      var tokens = 0;
      final sw = Stopwatch()..start();
      for (var i = 0; i < runs; i++) {
        tokens = grammar.tokenizeLine(line).tokens.length;
      }
      final ms = sw.elapsedMicroseconds / runs / 1000;
      print(
        '${language.padRight(10)} ${'${line.length}'.padLeft(6)} chars: '
        '${ms.toStringAsFixed(1).padLeft(8)} ms, $tokens tokens, '
        '${(ms * 1000 / line.length).toStringAsFixed(2)} µs/char',
      );
    }
  }
}
