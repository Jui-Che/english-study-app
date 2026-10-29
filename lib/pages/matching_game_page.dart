import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../logic/grouping.dart';
import '../models.dart';
import '../widgets/word_tile.dart';
import '../widgets/group_card.dart' show formatSeconds;

/// 配對遊戲：一組 20 字拆成 4 回合，每回合左邊英文、右邊中文各 5 張，點兩邊配對。
class MatchingGamePage extends StatefulWidget {
  const MatchingGamePage({super.key, required this.group});

  final WordGroup group;

  @override
  State<MatchingGamePage> createState() => _MatchingGamePageState();
}

enum _Side { left, right }

class _MatchingGamePageState extends State<MatchingGamePage> {
  late List<List<Word>> _rounds;
  int _round = 0;
  late List<Word> _left, _right;
  String? _selLeft, _selRight;
  String? _wrongLeft, _wrongRight;
  // 左右分開記：兩個字中文解釋相同時，英文 A 可能配到 B 的中文卡
  final Set<String> _matchedLeft = {}, _matchedRight = {};
  final Set<String> _missed = {};
  int _correct = 0, _mistakes = 0;
  bool _busy = false;
  bool _finished = false;
  bool _newRecord = false;
  final _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _rounds = splitRounds([...widget.group.words]..shuffle());
    _round = 0;
    _correct = 0;
    _mistakes = 0;
    _missed.clear();
    _finished = false;
    _newRecord = false;
    _stopwatch
      ..reset()
      ..start();
    _setupRound();
  }

  void _setupRound() {
    final words = _rounds[_round];
    _left = [...words]..shuffle();
    _right = [...words]..shuffle();
    _matchedLeft.clear();
    _matchedRight.clear();
    _selLeft = _selRight = _wrongLeft = _wrongRight = null;
  }

  String _meaningOf(String id) => _rounds[_round].firstWhere((w) => w.word == id).meaning;

  void _tap(_Side side, String id) {
    if (_busy || (side == _Side.left ? _matchedLeft : _matchedRight).contains(id)) return;
    setState(() {
      if (side == _Side.left) {
        _selLeft = _selLeft == id ? null : id;
      } else {
        _selRight = _selRight == id ? null : id;
      }
    });
    if (_selLeft != null && _selRight != null) _check();
  }

  Future<void> _check() async {
    final l = _selLeft!, r = _selRight!;
    if (l == r || _meaningOf(l) == _meaningOf(r)) {
      setState(() {
        _matchedLeft.add(l);
        _matchedRight.add(r);
        _correct++;
        _selLeft = _selRight = null;
      });
      if (_matchedLeft.length == _rounds[_round].length) {
        _busy = true;
        await Future.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        _busy = false;
        if (_round + 1 < _rounds.length) {
          setState(() {
            _round++;
            _setupRound();
          });
        } else {
          await _finish();
        }
      }
    } else {
      setState(() {
        _mistakes++;
        _missed.addAll([l, r]);
        _wrongLeft = l;
        _wrongRight = r;
        _busy = true;
      });
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() {
        _wrongLeft = _wrongRight = _selLeft = _selRight = null;
        _busy = false;
      });
    }
  }

  double get _accuracy => _correct / (_correct + _mistakes);

  Future<void> _finish() async {
    _stopwatch.stop();
    final store = AppScope.of(context).store;
    final record = await store.recordScore(
      widget.group.id,
      BestScore(accuracy: _accuracy, seconds: _stopwatch.elapsed.inSeconds),
    );
    if (!mounted) return;
    setState(() {
      _finished = true;
      _newRecord = record;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('配對：${widget.group.name}')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _finished ? _buildResult(context) : _buildBoard(context),
          ),
        ),
      ),
    );
  }

  Widget _buildBoard(BuildContext context) {
    final roundLen = _rounds[_round].length;
    final progress = (_round + _matchedLeft.length / roundLen) / _rounds.length;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Text('第 ${_round + 1} / ${_rounds.length} 回合', style: t.titleMedium),
              const Spacer(),
              Text('錯誤 $_mistakes 次', style: t.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _column(_left, _Side.left)),
                const SizedBox(width: 12),
                Expanded(child: _column(_right, _Side.right)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _column(List<Word> words, _Side side) {
    final isLeft = side == _Side.left;
    return Column(
      children: [
        for (final w in words)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: _MatchCard(
                text: isLeft ? w.word : w.meaning,
                english: isLeft,
                state: (isLeft ? _matchedLeft : _matchedRight).contains(w.word)
                    ? _CardState.matched
                    : (isLeft ? _wrongLeft : _wrongRight) == w.word
                        ? _CardState.wrong
                        : (isLeft ? _selLeft : _selRight) == w.word
                            ? _CardState.selected
                            : _CardState.normal,
                onTap: () => _tap(side, w.word),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResult(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final missed = _missed.map(scope.repo.find).whereType<Word>().toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.emoji_events, size: 64, color: Colors.amber.shade700),
        const SizedBox(height: 8),
        Text('完成！', style: t.headlineMedium, textAlign: TextAlign.center),
        if (_newRecord)
          Text('新紀錄 🎉', style: t.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Stat(label: '正確率', value: '${(_accuracy * 100).round()}%'),
            const SizedBox(width: 32),
            _Stat(label: '用時', value: formatSeconds(_stopwatch.elapsed.inSeconds)),
            const SizedBox(width: 32),
            _Stat(label: '配錯', value: '$_mistakes 次'),
          ],
        ),
        const SizedBox(height: 24),
        if (missed.isNotEmpty) ...[
          Row(
            children: [
              Text('這些字要再加強', style: t.titleMedium),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.star),
                label: const Text('全部加入收藏'),
                onPressed: () => scope.store.addFavorites(missed.map((w) => w.word)),
              ),
            ],
          ),
          for (final w in missed) WordTile(word: w),
        ] else
          Text('全部一次配對成功，太棒了！', style: t.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              icon: const Icon(Icons.replay),
              label: const Text('再玩一次'),
              onPressed: () => setState(_start),
            ),
          ],
        ),
      ],
    );
  }
}

enum _CardState { normal, selected, wrong, matched }

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.text,
    required this.english,
    required this.state,
    required this.onTap,
  });

  final String text;
  final bool english;
  final _CardState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final (bg, border) = switch (state) {
      _CardState.normal => (c.surfaceContainerHighest, c.outlineVariant),
      _CardState.selected => (c.primaryContainer, c.primary),
      _CardState.wrong => (c.errorContainer, c.error),
      _CardState.matched => (Colors.green.withValues(alpha: 0.15), Colors.green),
    };
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: state == _CardState.matched ? 0.35 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: 2),
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: english ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: t.bodyMedium),
      ],
    );
  }
}
