import 'package:flutter_test/flutter_test.dart';

import '../tool/build_dictionary.dart' show balanceBrackets, shortMeaning, splitSenses;
import 'helpers.dart';

void main() {
  test('拆解意思時不切開括號裡的逗號', () {
    expect(splitSenses('使參與[陷入，牽扯到]; 嬋媛'), ['使參與[陷入，牽扯到]', '嬋媛']);
    expect(splitSenses('節目, 節目單, 程序'), ['節目', '節目單', '程序']);
    expect(splitSenses('(使)起床, 起來'), ['(使)起床', '起來']);
    expect(shortMeaning(['使參與[陷入，牽扯到]; 嬋媛']), ('', '使參與[陷入，牽扯到]'));
    expect(shortMeaning(['n. 蘋果, 傢伙', '[醫] 蘋果']), ('n.', '蘋果；傢伙'));
  });

  test('修正原始資料的括號錯誤', () {
    expect(balanceBrackets('威利(人名）'), '威利（人名）');
    expect(balanceBrackets('伊頓（姓氏））'), '伊頓（姓氏）');
    expect(balanceBrackets('芬斯伯裡（（英國倫敦一區）'), '芬斯伯裡（英國倫敦一區）');
    expect(balanceBrackets('琳賽〔女子名）'), '琳賽（女子名）');
    expect(balanceBrackets('使參與[陷入，牽扯到]'), '使參與[陷入，牽扯到]');
  });

  test('字庫裡所有簡短解釋的括號都成對', () {
    const pairs = {'[': ']', '(': ')', '（': '）', '【': '】'};
    final broken = [
      for (final w in loadTestRepo().allEntries)
        if (pairs.entries.any((p) => p.key.allMatches(w.meaning).length != p.value.allMatches(w.meaning).length))
          '${w.word}: ${w.meaning}',
    ];
    expect(broken, isEmpty, reason: broken.take(20).join('\n'));
  });
}
