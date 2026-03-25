import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Animated typing indicator shown while the AI is generating a response.
///
/// Displays a row of pulsing dots alongside a rotating status label
/// (e.g. "AI is thinking…", "Generating response…").
/// Pass [isToolCalling] to switch to the tool-call phrase set (orange tint).
class TypingIndicator extends StatefulWidget {
  final bool isToolCalling;

  const TypingIndicator({super.key, this.isToolCalling = false});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  final List<AnimationController> _dotControllers = [];
  final List<Animation<double>> _dotAnimations = [];

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  int _phraseIndex = 0;
  Timer? _phraseTimer;

  List<String> get _phrases =>
      widget.isToolCalling ? TypingPhrases.toolCalling : TypingPhrases.normal;

  Color get _dotColor =>
      widget.isToolCalling ? AppColors.toolCallColor : Colors.white70;

  @override
  void initState() {
    super.initState();

    // Dot bounce animations – staggered by 160 ms each.
    for (int i = 0; i < 3; i++) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      );
      final animation = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
      _dotControllers.add(controller);
      _dotAnimations.add(animation);
      Future.delayed(Duration(milliseconds: i * 160), () {
        if (mounted) controller.repeat(reverse: true);
      });
    }

    // Fade animation for phrase transitions.
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 1.0,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    // Rotate phrases every 3 seconds.
    _phraseTimer = Timer.periodic(
      AppDurations.typingPhraseRotation,
      (_) => _rotatePhrase(),
    );
  }

  void _rotatePhrase() {
    if (!mounted || _phrases.length <= 1) return;
    _fadeController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _phraseIndex = (_phraseIndex + 1) % _phrases.length;
      });
      _fadeController.forward();
    });
  }

  @override
  void dispose() {
    for (final c in _dotControllers) {
      c.dispose();
    }
    _fadeController.dispose();
    _phraseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.bubbleAssistant,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing dots
            ...List.generate(3, (i) {
              return FadeTransition(
                opacity: _dotAnimations[i],
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
            const SizedBox(width: 10),
            // Rotating status label
            FadeTransition(
              opacity: _fadeAnimation,
              child: Text(
                _phrases[_phraseIndex],
                style: TextStyle(
                  color: _dotColor,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
