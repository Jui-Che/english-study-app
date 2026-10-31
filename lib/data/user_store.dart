import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../models.dart';
import '../platform/platform.dart';

/// 使用者自己的資料：收藏的單字、待調整的單字、各組最佳成績。
///
/// 整份存成一段 JSON：桌面版存檔案、網頁版存 localStorage（見 platform/）。
/// 之後要跨裝置同步時，換成 Supabase 等雲端服務即可，介面（isFavorite / toggleFavorite …）可以維持不變。
class UserStore extends ChangeNotifier {
  UserStore(UserDataStorage this._storage);

  /// 不存檔的版本，給測試用。
  UserStore.memory() : _storage = null;

  final UserDataStorage? _storage;

  /// 單字 → 收藏時間。用 LinkedHashMap 保留加入順序。
  final Map<String, DateTime> _favorites = {};
  final Map<String, BestScore> _bestScores = {};

  /// 使用者調整過的迷你模式視窗大小（邏輯像素）。
  Size? _miniWindowSize;

  /// 等待修正的字 → 要處理的項目（解釋、例句）、使用者的備註、回報時間。
  final Map<String, ({Set<FixKind> kinds, String note, DateTime at})> _toFix = {};

  static Future<UserStore> open() async {
    final store = UserStore(UserDataStorage());
    await store._load();
    return store;
  }

  Future<void> _load() async {
    final raw = await _storage?.read();
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final favs = (data['favorites'] as Map<String, dynamic>? ?? {});
      favs.forEach((k, v) => _favorites[k] = DateTime.parse(v as String));
      final scores = (data['bestScores'] as Map<String, dynamic>? ?? {});
      scores.forEach((k, v) => _bestScores[k] = BestScore.fromJson(v as Map<String, dynamic>));
      if (data['miniWindow'] case {'width': final num w, 'height': final num h}) {
        _miniWindowSize = Size(w.toDouble(), h.toDouble());
      }
      final toFix = (data['toFix'] as Map<String, dynamic>? ?? {});
      toFix.forEach((k, v) {
        final m = v as Map<String, dynamic>;
        _toFix[k] = (
          // 舊版資料沒有 kinds，當作中文解釋
          kinds: {for (final n in m['kinds'] as List? ?? ['meaning']) FixKind.values.byName(n as String)},
          note: m['note'] as String? ?? '',
          at: DateTime.parse(m['at'] as String),
        );
      });
    } on FormatException catch (e) {
      debugPrint('user_data.json 格式錯誤，略過：$e');
    }
  }

  Future<void> _save() async {
    await _storage?.write(jsonEncode({
      'favorites': _favorites.map((k, v) => MapEntry(k, v.toIso8601String())),
      'bestScores': _bestScores.map((k, v) => MapEntry(k, v.toJson())),
      if (_miniWindowSize case final size?) 'miniWindow': {'width': size.width, 'height': size.height},
      'toFix': _toFix.map((k, v) => MapEntry(k, {
            'kinds': [for (final kind in v.kinds) kind.name],
            'note': v.note,
            'at': v.at.toIso8601String(),
          })),
    }));
  }

  /// 依收藏時間排序（舊 → 新）的單字清單。
  List<String> get favorites => _favorites.keys.toList();

  bool isFavorite(String word) => _favorites.containsKey(word);

  Future<void> toggleFavorite(String word) async {
    if (_favorites.remove(word) == null) _favorites[word] = DateTime.now();
    notifyListeners();
    await _save();
  }

  Future<void> addFavorites(Iterable<String> words) async {
    for (final w in words) {
      _favorites.putIfAbsent(w, DateTime.now);
    }
    notifyListeners();
    await _save();
  }

  /// 依回報時間排序（舊 → 新）的待調整單字。
  List<String> get toFix => _toFix.keys.toList();

  bool needsFix(String word) => _toFix.containsKey(word);

  String? toFixNote(String word) => _toFix[word]?.note;

  Set<FixKind> toFixKinds(String word) => _toFix[word]?.kinds ?? const {};

  /// 加入或更新待調整；[kinds] 為空時等於移除。
  Future<void> markToFix(String word, String note, Set<FixKind> kinds) async {
    if (kinds.isEmpty) return removeToFix([word]);
    _toFix[word] = (kinds: {...kinds}, note: note.trim(), at: DateTime.now());
    notifyListeners();
    await _save();
  }

  Future<void> removeToFix(Iterable<String> words) async {
    words.toList().forEach(_toFix.remove);
    notifyListeners();
    await _save();
  }

  Size? get miniWindowSize => _miniWindowSize;

  Future<void> setMiniWindowSize(Size size) async {
    if (size == _miniWindowSize) return;
    _miniWindowSize = size;
    await _save();
  }

  BestScore? bestScore(String groupId) => _bestScores[groupId];

  /// 回傳 true 表示刷新了最佳紀錄。
  Future<bool> recordScore(String groupId, BestScore score) async {
    if (!score.isBetterThan(_bestScores[groupId])) return false;
    _bestScores[groupId] = score;
    notifyListeners();
    await _save();
    return true;
  }
}
