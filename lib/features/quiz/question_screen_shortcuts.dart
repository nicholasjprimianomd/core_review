import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Intents for [QuestionScreen] keyboard shortcuts.
class GoPreviousQuestionIntent extends Intent {
  const GoPreviousQuestionIntent();
}

class GoNextQuestionIntent extends Intent {
  const GoNextQuestionIntent();
}

class JumpFirstQuestionIntent extends Intent {
  const JumpFirstQuestionIntent();
}

class JumpLastQuestionIntent extends Intent {
  const JumpLastQuestionIntent();
}

class SubmitOrAdvanceQuestionIntent extends Intent {
  const SubmitOrAdvanceQuestionIntent();
}

class OpenQuestionListIntent extends Intent {
  const OpenQuestionListIntent();
}

class CloseEndDrawerIntent extends Intent {
  const CloseEndDrawerIntent();
}

class ShowKeyboardShortcutsHelpIntent extends Intent {
  const ShowKeyboardShortcutsHelpIntent();
}

class CopyQuestionHighlightsIntent extends Intent {
  const CopyQuestionHighlightsIntent();
}

class SelectChoiceDigitIntent extends Intent {
  const SelectChoiceDigitIntent(this.digitOneToNine);
  final int digitOneToNine;
}

class SelectChoiceKeyIntent extends Intent {
  const SelectChoiceKeyIntent(this.choiceKey);
  final String choiceKey;
}

/// Base shortcuts (choice letters are merged in [mergeQuizChoiceLetterShortcuts]).
Map<ShortcutActivator, Intent> quizQuestionBaseShortcuts() {
  return <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.arrowLeft): const GoPreviousQuestionIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowRight): const GoNextQuestionIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
        const GoPreviousQuestionIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
        const GoNextQuestionIntent(),
    const SingleActivator(LogicalKeyboardKey.bracketLeft): const GoPreviousQuestionIntent(),
    const SingleActivator(LogicalKeyboardKey.bracketRight): const GoNextQuestionIntent(),
    const SingleActivator(LogicalKeyboardKey.home): const JumpFirstQuestionIntent(),
    const SingleActivator(LogicalKeyboardKey.end): const JumpLastQuestionIntent(),
    const SingleActivator(LogicalKeyboardKey.enter): const SubmitOrAdvanceQuestionIntent(),
    const SingleActivator(LogicalKeyboardKey.keyG, control: true):
        const OpenQuestionListIntent(),
    const SingleActivator(LogicalKeyboardKey.keyL, control: true, shift: true):
        const OpenQuestionListIntent(),
    const SingleActivator(LogicalKeyboardKey.escape): const CloseEndDrawerIntent(),
    const SingleActivator(LogicalKeyboardKey.slash, shift: true):
        const ShowKeyboardShortcutsHelpIntent(),
    const SingleActivator(LogicalKeyboardKey.slash, control: true):
        const ShowKeyboardShortcutsHelpIntent(),
    const SingleActivator(LogicalKeyboardKey.keyH, control: true, shift: true):
        const CopyQuestionHighlightsIntent(),
    const SingleActivator(LogicalKeyboardKey.digit1): const SelectChoiceDigitIntent(1),
    const SingleActivator(LogicalKeyboardKey.digit2): const SelectChoiceDigitIntent(2),
    const SingleActivator(LogicalKeyboardKey.digit3): const SelectChoiceDigitIntent(3),
    const SingleActivator(LogicalKeyboardKey.digit4): const SelectChoiceDigitIntent(4),
    const SingleActivator(LogicalKeyboardKey.digit5): const SelectChoiceDigitIntent(5),
    const SingleActivator(LogicalKeyboardKey.digit6): const SelectChoiceDigitIntent(6),
    const SingleActivator(LogicalKeyboardKey.digit7): const SelectChoiceDigitIntent(7),
    const SingleActivator(LogicalKeyboardKey.digit8): const SelectChoiceDigitIntent(8),
    const SingleActivator(LogicalKeyboardKey.digit9): const SelectChoiceDigitIntent(9),
  };
}

/// Adds A–Z activators when [choices] contains that option key (case-sensitive).
void mergeQuizChoiceLetterShortcuts(
  Map<ShortcutActivator, Intent> into,
  Map<String, String> choices,
) {
  const letterKeys = <String, LogicalKeyboardKey>{
    'A': LogicalKeyboardKey.keyA,
    'B': LogicalKeyboardKey.keyB,
    'C': LogicalKeyboardKey.keyC,
    'D': LogicalKeyboardKey.keyD,
    'E': LogicalKeyboardKey.keyE,
    'F': LogicalKeyboardKey.keyF,
    'G': LogicalKeyboardKey.keyG,
    'H': LogicalKeyboardKey.keyH,
    'I': LogicalKeyboardKey.keyI,
    'J': LogicalKeyboardKey.keyJ,
    'K': LogicalKeyboardKey.keyK,
    'L': LogicalKeyboardKey.keyL,
    'M': LogicalKeyboardKey.keyM,
    'N': LogicalKeyboardKey.keyN,
    'O': LogicalKeyboardKey.keyO,
    'P': LogicalKeyboardKey.keyP,
    'Q': LogicalKeyboardKey.keyQ,
    'R': LogicalKeyboardKey.keyR,
    'S': LogicalKeyboardKey.keyS,
    'T': LogicalKeyboardKey.keyT,
    'U': LogicalKeyboardKey.keyU,
    'V': LogicalKeyboardKey.keyV,
    'W': LogicalKeyboardKey.keyW,
    'X': LogicalKeyboardKey.keyX,
    'Y': LogicalKeyboardKey.keyY,
    'Z': LogicalKeyboardKey.keyZ,
  };
  for (final entry in letterKeys.entries) {
    if (!choices.containsKey(entry.key)) {
      continue;
    }
    into[SingleActivator(entry.value)] = SelectChoiceKeyIntent(entry.key);
    into[SingleActivator(entry.value, shift: true)] = SelectChoiceKeyIntent(entry.key);
  }
}

void showQuizKeyboardShortcutsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Keyboard shortcuts'),
        content: const SingleChildScrollView(
          child: Text(
            'Navigation\n'
            '  Left / Right — Previous / next question\n'
            '  Alt+Left / Alt+Right — Same (when arrow keys adjust text selection)\n'
            '  [ / ] — Previous / next question\n'
            '  Home / End — First / last question\n'
            '\n'
            'Answering (when a choice is not locked)\n'
            '  1–9 — Select choice by position\n'
            '  A–Z — Select choice if that letter is an option key\n'
            '  Enter — Next part, submit answer, or go to next if already answered\n'
            '\n'
            'Exam list\n'
            '  Ctrl+G or Ctrl+Shift+L — Open question list (drawer when panel is hidden)\n'
            '  Esc — Close question list drawer\n'
            '\n'
            'Highlights\n'
            '  Ctrl+Shift+H — Copy all highlighted text on this question\n'
            '\n'
            'Help\n'
            '  ? or Ctrl+/ — Show this dialog',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
