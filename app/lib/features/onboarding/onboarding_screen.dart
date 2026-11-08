import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/big_button.dart';
import '../../core/widgets/choice_card.dart';
import '../../l10n/app_localizations.dart';

/// Two steps: language, then display mode. Both apply live as you tap.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final text = Theme.of(context).textTheme;

    final Widget content = _step == 0
        ? Column(
            key: const ValueKey('lang'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.chooseLanguage,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Tokens.s2),
              Text(l.chooseLanguageHint, style: text.bodyLarge),
              const SizedBox(height: Tokens.s5),
              ChoiceCard(
                title: l.languageEnglish,
                icon: Icons.translate,
                color: Tokens.indigo,
                selected: settings.languageCode == 'en',
                onTap: () => notifier.setLanguage('en'),
                titleStyle: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: Tokens.s3),
              ChoiceCard(
                title: l.languageUrdu,
                icon: Icons.translate,
                color: Tokens.primary,
                selected: settings.languageCode == 'ur',
                onTap: () => notifier.setLanguage('ur'),
                titleStyle: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFamily: AppTheme.urduFont,
                  height: 1.8,
                ),
              ),
            ],
          )
        : Column(
            key: const ValueKey('mode'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.whoWillUse,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Tokens.s2),
              Text(l.whoWillUseHint, style: text.bodyLarge),
              const SizedBox(height: Tokens.s5),
              ChoiceCard(
                icon: Icons.text_increase,
                color: Tokens.saffronDeep,
                title: l.modeSimpleTitle,
                subtitle: l.modeSimpleHint,
                selected: settings.simpleMode,
                onTap: () => notifier.setSimpleMode(true),
              ),
              const SizedBox(height: Tokens.s3),
              ChoiceCard(
                icon: Icons.tune,
                color: Tokens.violet,
                title: l.modeStandardTitle,
                subtitle: l.modeStandardHint,
                selected: !settings.simpleMode,
                onTap: () => notifier.setSimpleMode(false),
              ),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: Tokens.heroGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: Tokens.s3),
            Text(l.appTitle),
          ],
        ),
        leading: _step == 0
            ? null
            : IconButton(
                tooltip: l.back,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _step = 0),
              ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s4),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: content,
                  ),
                ),
              ),
              const SizedBox(height: Tokens.s3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 2; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _step ? 28 : 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: i == _step
                            ? Tokens.saffron
                            : Theme.of(context).colorScheme.outline,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Tokens.s3),
              BigButton(
                label: l.continueLabel,
                icon: Icons.arrow_forward,
                onPressed: () async {
                  if (_step == 0) {
                    setState(() => _step = 1);
                  } else {
                    await notifier.setOnboardingDone();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
