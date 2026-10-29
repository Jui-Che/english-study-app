/// 每組學習的單字數。
const groupSize = 20;

/// 配對遊戲每回合的配對數（手機畫面一次放 5 對剛好）。
const pairsPerRound = 5;

/// 把清單切成每段 [size] 個。
List<List<T>> chunk<T>(List<T> items, int size) => [
      for (var i = 0; i < items.length; i += size)
        items.sublist(i, i + size > items.length ? items.length : i + size),
    ];

/// 把一組單字切成配對回合；最後只剩 1 個字時併入前一回合（1 對無法配對）。
List<List<T>> splitRounds<T>(List<T> words, {int size = pairsPerRound}) {
  final rounds = chunk(words, size);
  if (rounds.length > 1 && rounds.last.length == 1) {
    final last = rounds.removeLast();
    rounds.last = [...rounds.last, ...last];
  }
  return rounds;
}
