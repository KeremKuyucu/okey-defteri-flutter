import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../models/game_models.dart';
import '../theme/app_theme.dart';
import '../services/storage_service.dart';
import '../widgets/player_card.dart';
import '../widgets/team_score_bar.dart';
import '../widgets/americano_score_dialog.dart';
import '../widgets/ad_banner_widget.dart';
import 'score_history_screen.dart';
import '../services/settings_service.dart';
import '../services/localization_service.dart';

class AmericanoGameScreen extends StatefulWidget {
  final Game game;

  const AmericanoGameScreen({super.key, required this.game});

  @override
  State<AmericanoGameScreen> createState() => _AmericanoGameScreenState();
}

class _AmericanoGameScreenState extends State<AmericanoGameScreen>
    with TickerProviderStateMixin {
  late Game _game;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _bannerController;
  late Animation<double> _bannerAnimation;

  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoaded = false;
  
  String get _interstitialAdUnitId {
    if (kDebugMode) {
      return defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? 'ca-app-pub-4674396016131447/8600025809'
        : 'ca-app-pub-3940256099942544/4411468910';
  }

  void _loadInterstitialAd() {
    if (kIsWeb) return;
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('InterstitialAd loaded.');
          _interstitialAd = ad;
          _isInterstitialAdLoaded = true;
        },
        onAdFailedToLoad: (LoadAdError error) {
          debugPrint('InterstitialAd failed to load: $error');
          _isInterstitialAdLoaded = false;
          _interstitialAd = null;
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _game = widget.game;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _bannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _bannerAnimation = CurvedAnimation(
      parent: _bannerController,
      curve: Curves.easeOut,
    );
    _loadInterstitialAd();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bannerController.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  Future<void> _saveGame() async {
    await StorageService.saveActiveGame(_game);
  }

  AmericanoRound? get _currentRound =>
      AmericanoRound.forRound(_game.currentRound);

  /// Bireysel oyuncu ceza dialogu (işlek / hile)
  Future<void> _openPenaltyDialog(Player player) async {
    if (_game.isFinished) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Localization.t('game.finished'))),
      );
      return;
    }
    AudioVibrationService.playClickSound();
    AudioVibrationService.vibrate();

    bool islek = false;
    bool hile = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppTheme.surfaceDark,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Text('🎯', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  player.name,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                value: islek,
                onChanged: (v) => setS(() => islek = v ?? false),
                title: Text(Localization.t('americano.islek'),
                    style: const TextStyle(color: AppTheme.textPrimary)),
                activeColor: AppTheme.dangerRed,
                checkColor: Colors.white,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: hile,
                onChanged: (v) => setS(() => hile = v ?? false),
                title: Text(Localization.t('americano.hile'),
                    style: const TextStyle(color: AppTheme.textPrimary)),
                activeColor: AppTheme.dangerRed,
                checkColor: Colors.white,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(Localization.t('common.cancel'),
                  style: const TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.dangerRed),
              child: Text(Localization.t('common.save')),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (confirmed != true) return;
    if (!islek && !hile) return;

    final now = DateTime.now();
    setState(() {
      if (islek) {
        player.scores.add(ScoreEntry(
          id: '${now.millisecondsSinceEpoch}_${player.id}_islek',
          type: ScoreType.americanoIslek,
          points: 50,
          timestamp: now,
          roundNumber: _game.currentRound,
        ));
      }
      if (hile) {
        player.scores.add(ScoreEntry(
          id: '${now.millisecondsSinceEpoch}_${player.id}_hile',
          type: ScoreType.americanoHile,
          points: 50,
          timestamp: now,
          roundNumber: _game.currentRound,
        ));
      }
    });
    await _saveGame();
  }

  /// Tur sonu puan giriş dialogunu aç
  Future<void> _openRoundEndDialog() async {
    if (_game.isFinished) return;
    AudioVibrationService.playClickSound();
    AudioVibrationService.vibrateHeavy();

    final results = await showDialog<List<MapEntry<String, List<ScoreEntry>>>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AmericanoRoundScoreDialog(
        players: _game.allPlayers,
        roundNumber: _game.currentRound,
      ),
    );

    if (!mounted) return;
    if (results == null) return;

    setState(() {
      for (final entry in results) {
        final player =
            _game.allPlayers.firstWhere((p) => p.id == entry.key);
        player.scores.addAll(entry.value);
      }
    });
    await _saveGame();

    // Kazananı göster
    final winnerEntry = results.firstWhere(
      (e) => e.value.any((s) => s.type == ScoreType.americanoKazandi),
      orElse: () => MapEntry('', []),
    );
    if (winnerEntry.key.isNotEmpty && mounted) {
      final winner =
          _game.allPlayers.firstWhere((p) => p.id == winnerEntry.key);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.t('americano.round_winner', args: [winner.name]),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppTheme.accentGold,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _undoLastScore(Player player) {
    if (_game.isFinished) return;
    if (player.scores.isEmpty) return;
    AudioVibrationService.playClickSound();
    AudioVibrationService.vibrateHeavy();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Son Puanı Geri Al',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          Localization.t('game.process_cancel',
              args: [player.name, _game.currentRound]),
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Localization.t('common.cancel'),
                style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => player.scores.removeLast());
              _saveGame();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.dangerRed),
            child: const Text('Geri Al'),
          ),
        ],
      ),
    );
  }

  void _advanceRound() {
    setState(() {
      _game.currentRound++;
    });
    _bannerController
      ..reset()
      ..forward();
    _saveGame();

    final isLast = _game.currentRound == 12;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isLast
              ? Localization.t('americano.last_round')
              : Localization.t('americano.round_of',
                  args: [_game.currentRound]),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor:
            isLast ? AppTheme.accentGold : AppTheme.lightGreen,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _nextRound() {
    if (_game.isFinished) return;
    if (_game.currentRound >= 12) {
      _endGame();
      return;
    }
    AudioVibrationService.playClickSound();
    AudioVibrationService.vibrateHeavy();
    
    if (_isInterstitialAdLoaded && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _isInterstitialAdLoaded = false;
          _interstitialAd = null;
          _advanceRound();
          _loadInterstitialAd();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _isInterstitialAdLoaded = false;
          _interstitialAd = null;
          _advanceRound();
          _loadInterstitialAd();
        },
      );
      _interstitialAd!.show();
    } else {
      _advanceRound();
    }
  }

  void _prevRound() {
    if (_game.isFinished) return;
    if (_game.currentRound <= 1) return;
    AudioVibrationService.playClickSound();
    AudioVibrationService.vibrateHeavy();

    final prevRound = _game.currentRound - 1;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(Localization.t('game.prev_round_confirm_title'),
            style: const TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          Localization.t('game.prev_round_confirm', args: [prevRound]),
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Localization.t('common.cancel'),
                style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                for (final p in _game.allPlayers) {
                  p.scores.removeWhere(
                      (s) => s.roundNumber == _game.currentRound);
                }
                _game.currentRound = prevRound;
              });
              _saveGame();
              Navigator.pop(ctx);
              _bannerController
                ..reset()
                ..forward();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    Localization.t('game.round', args: [_game.currentRound]),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: AppTheme.dangerRed,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.dangerRed),
            child: Text(Localization.t('game.prev_round_undo')),
          ),
        ],
      ),
    );
  }

  void _endGame() {
    if (_game.isFinished) return;
    AudioVibrationService.playClickSound();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(Localization.t('game.end_game'),
            style: const TextStyle(color: AppTheme.textPrimary)),
        content: Text(Localization.t('game.end_game_confirm'),
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Localization.t('common.cancel'),
                style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _game.isFinished = true;
                _game.endedAt = DateTime.now();
              });
              _saveGame();
              StorageService.clearActiveGame();
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.dangerRed),
            child: Text(Localization.t('common.yes')),
          ),
        ],
      ),
    );
  }

  void _showRules() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Text('🃏', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(Localization.t('americano.game_rules'),
                style: const TextStyle(color: AppTheme.accentGold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Localization.t('americano.rules_text'),
                style: const TextStyle(
                    color: AppTheme.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 16),
              const Divider(color: AppTheme.surfaceCardLight),
              const SizedBox(height: 12),
              ...AmericanoRound.rounds.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _game.currentRound == r.roundNumber
                                ? AppTheme.accentGold
                                : AppTheme.surfaceCardLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${r.roundNumber}',
                            style: TextStyle(
                              color: _game.currentRound == r.roundNumber
                                  ? Colors.black
                                  : AppTheme.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            r.title,
                            style: TextStyle(
                              color: _game.currentRound == r.roundNumber
                                  ? AppTheme.textPrimary
                                  : AppTheme.textMuted,
                              fontSize: 13,
                              fontWeight:
                                  _game.currentRound == r.roundNumber
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.lightGreen),
            child: Text(Localization.t('common.close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final round = _currentRound;
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const SizedBox(height: 4),
            // Americano tur kural banneri
            if (round != null) _buildRoundBanner(round),
            const SizedBox(height: 6),
            // Takım toplam skorları — solo modda gizlenir
            if (!_game.isAmericanoSolo)
              TeamScoreBar(team1: _game.team1, team2: _game.team2),
            if (!_game.isAmericanoSolo) const SizedBox(height: 6),
            Expanded(child: _buildGameTable()),
            const AdBannerWidget(),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildRoundBanner(AmericanoRound round) {
    final isLast = _game.currentRound == 12;
    return FadeTransition(
      opacity: _bannerAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.3),
          end: Offset.zero,
        ).animate(_bannerAnimation),
        child: GestureDetector(
          onTap: _showRules,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: isLast
                  ? AppTheme.goldGradient
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.surfaceCard,
                        AppTheme.surfaceCardLight,
                      ],
                    ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isLast
                    ? AppTheme.accentGold
                    : AppTheme.lightGreen.withValues(alpha: 0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: (isLast ? AppTheme.accentGold : AppTheme.lightGreen)
                      .withValues(alpha: 0.15),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              children: [
                Text(round.emoji,
                    style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Localization.t('americano.round_of',
                            args: [_game.currentRound]),
                        style: TextStyle(
                          color: isLast
                              ? Colors.black87
                              : AppTheme.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        round.title,
                        style: TextStyle(
                          color: isLast
                              ? Colors.black
                              : AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.info_outline,
                  color: isLast
                      ? Colors.black54
                      : AppTheme.textMuted,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: AppTheme.textPrimary, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🃏 ',
                        style: TextStyle(fontSize: 16)),
                    Text(
                      Localization.t('americano.mode_name'),
                      style: const TextStyle(
                        color: AppTheme.accentGold,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                Text(
                  Localization.t('americano.round_of',
                      args: [_game.currentRound]),
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.textPrimary),
            color: AppTheme.surfaceDark,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            itemBuilder: (ctx) => [
              _popupItem('history', Icons.history,
                  Localization.t('game.history')),
              _popupItem('rules', Icons.menu_book,
                  Localization.t('americano.game_rules')),
              if (!_game.isFinished)
                _popupItem('end', Icons.flag,
                    Localization.t('game.end_game')),
            ],
            onSelected: (value) {
              switch (value) {
                case 'history':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) =>
                          ScoreHistoryScreen(game: _game),
                    ),
                  );
                case 'rules':
                  _showRules();
                case 'end':
                  _endGame();
              }
            },
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _popupItem(
      String value, IconData icon, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 20),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildGameTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Geniş ekranlarda aşırı büyümeyi önlemek için maksimum genişlik sınırı uygulanır.
        final effectiveWidth = constraints.maxWidth.clamp(0.0, 520.0);
        final tableSize = effectiveWidth * 0.42;
        const double gap = 12.0;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: FittedBox(
              fit: BoxFit.contain,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Üst oyuncu
                  GestureDetector(
                    onTap: () => _openPenaltyDialog(_game.team1.player1),
                    onLongPress: () => _undoLastScore(_game.team1.player1),
                    child: PlayerCard(
                      player: _game.team1.player1,
                      team: _game.team1,
                      position: 0,
                      nickname: '',
                      onTap: () => _openPenaltyDialog(_game.team1.player1),
                      onToggleCiftli: () {},
                    ),
                  ),
                  const SizedBox(height: gap),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Sol oyuncu
                      GestureDetector(
                        onTap: () =>
                            _openPenaltyDialog(_game.team2.player2),
                        onLongPress: () =>
                            _undoLastScore(_game.team2.player2),
                        child: PlayerCard(
                          player: _game.team2.player2,
                          team: _game.team2,
                          position: 3,
                          nickname: '',
                          onTap: () =>
                              _openPenaltyDialog(_game.team2.player2),
                          onToggleCiftli: () {},
                        ),
                      ),
                      const SizedBox(width: gap),
                      // Masa
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (ctx, child) => GestureDetector(
                          onTap: _openRoundEndDialog,
                          child: Container(
                            width: tableSize,
                            height: tableSize,
                            decoration: BoxDecoration(
                              gradient: AppTheme.tableGradient,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color:
                                    AppTheme.accentGold.withValues(alpha: 0.4),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryGreen
                                      .withValues(alpha: 0.3),
                                  blurRadius: 24,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('🃏',
                                      style: TextStyle(fontSize: 28)),
                                  const SizedBox(height: 4),
                                  Text(
                                    Localization.t('americano.round_end'),
                                    style: const TextStyle(
                                      color: AppTheme.accentGold,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: gap),
                      // Sağ oyuncu
                      GestureDetector(
                        onTap: () =>
                            _openPenaltyDialog(_game.team2.player1),
                        onLongPress: () =>
                            _undoLastScore(_game.team2.player1),
                        child: PlayerCard(
                          player: _game.team2.player1,
                          team: _game.team2,
                          position: 1,
                          nickname: '',
                          onTap: () =>
                              _openPenaltyDialog(_game.team2.player1),
                          onToggleCiftli: () {},
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: gap),
                  // Alt oyuncu
                  GestureDetector(
                    onTap: () => _openPenaltyDialog(_game.team1.player2),
                    onLongPress: () => _undoLastScore(_game.team1.player2),
                    child: PlayerCard(
                      player: _game.team1.player2,
                      team: _game.team1,
                      position: 2,
                      nickname: '',
                      onTap: () => _openPenaltyDialog(_game.team1.player2),
                      onToggleCiftli: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard.withValues(alpha: 0.9),
        border: Border(
          top: BorderSide(
              color: AppTheme.lightGreen.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _bottomButton(
            icon: Icons.history,
            label: Localization.t('game.history'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => ScoreHistoryScreen(game: _game),
              ),
            ),
          ),
          if (!_game.isFinished) ...[
            if (_game.currentRound > 1)
              _bottomButton(
                icon: Icons.skip_previous_rounded,
                label: Localization.t('game.prev_round'),
                onTap: _prevRound,
                isDanger: true,
              ),
            // El bitti — masa merkezine de dokunulabilir ama kolaylık için buton
            _bottomButton(
              icon: Icons.casino_rounded,
              label: Localization.t('americano.round_end'),
              onTap: _openRoundEndDialog,
              isPrimary: true,
            ),
            _bottomButton(
              icon: Icons.skip_next_rounded,
              label: Localization.t('game.next_round'),
              onTap: _nextRound,
            ),
            _bottomButton(
              icon: Icons.flag_rounded,
              label: Localization.t('game.end_game'),
              onTap: _endGame,
              isDanger: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
    bool isDanger = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: isPrimary
            ? BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentGold.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              )
            : isDanger
            ? BoxDecoration(
                color: AppTheme.dangerRed.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.dangerRed.withValues(alpha: 0.3)),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isPrimary
                  ? Colors.black
                  : isDanger
                  ? AppTheme.dangerRed
                  : AppTheme.textSecondary,
              size: 20,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isPrimary
                    ? Colors.black
                    : isDanger
                    ? AppTheme.dangerRed
                    : AppTheme.textMuted,
                fontSize: 9,
                fontWeight: isPrimary || isDanger
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
