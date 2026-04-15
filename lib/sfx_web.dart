import 'dart:js' as js;

// Each note supports:
//   freq     – start frequency (Hz)
//   glide    – end frequency (Hz), optional smooth pitch slide
//   dur      – total duration (seconds)
//   vol      – peak volume 0.0–1.0
//   type     – sine / triangle / sawtooth / square  (default: sine)
//   attack   – fade-in time in seconds              (default: 0.006)
//   decay    – if true, uses exponential decay for natural organic sound (default: true)
//   overlap  – if true, starts simultaneously with previous note (default: false)
void playWebTone(List<Map<String, dynamic>> notes) {
  final buffer = StringBuffer();
  buffer.write('(function(){');
  buffer.write('var ctx=new(window.AudioContext||window.webkitAudioContext)();');
  buffer.write('var t=ctx.currentTime;');

  double offset = 0;
  for (final note in notes) {
    final freq    = (note['freq']    as num).toDouble();
    final dur     = (note['dur']     as num).toDouble();
    final vol     = ((note['vol']    as num?)?.toDouble())    ?? 0.35;
    final type    = (note['type']    as String?)              ?? 'sine';
    final attack  = ((note['attack'] as num?)?.toDouble())    ?? 0.006;
    final overlap = (note['overlap'] as bool?)                ?? false;
    final expDecay = (note['decay']  as bool?)                ?? true;
    final glide   = (note['glide']   as num?)?.toDouble();

    buffer.write('(function(){');
    buffer.write('var o=ctx.createOscillator();');
    buffer.write('var g=ctx.createGain();');
    buffer.write('o.connect(g);g.connect(ctx.destination);');
    buffer.write('o.type="$type";');
    buffer.write('o.frequency.setValueAtTime($freq,t+$offset);');
    if (glide != null) {
      buffer.write('o.frequency.linearRampToValueAtTime($glide,t+${offset + dur});');
    }
    buffer.write('g.gain.setValueAtTime(0.0001,t+$offset);');
    buffer.write('g.gain.linearRampToValueAtTime($vol,t+${offset + attack});');
    if (expDecay) {
      // exponential decay — sounds like real instruments (marimba, bell, piano)
      buffer.write('g.gain.exponentialRampToValueAtTime(0.0001,t+${offset + dur});');
    } else {
      buffer.write('g.gain.linearRampToValueAtTime(0.0001,t+${offset + dur});');
    }
    buffer.write('o.start(t+$offset);');
    buffer.write('o.stop(t+${offset + dur + 0.02});');
    buffer.write('})();');

    if (!overlap) offset += dur;
  }

  buffer.write('})()');
  js.context.callMethod('eval', [buffer.toString()]);
}
