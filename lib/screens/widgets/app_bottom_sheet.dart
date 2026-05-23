import 'package:flutter/material.dart';

class AppBottomSheet extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  const AppBottomSheet({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle. Tuned for *discoverability* on gesture-nav devices:
          // the OS swipe-up gesture bar lives right below the sheet, so the
          // handle has to read clearly enough that the user spots the
          // swipe-target before reflexively trying to dismiss with the
          // system gesture. 48×6 with `onSurfaceVariant @ 60%` gives a
          // visible-but-not-loud "you can grab me" affordance.
          Center(
            child: Container(
              width: 48,
              height: 6,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                // Long subtask descriptions used to wrap onto multiple
                // lines, pushing the rest of the sheet content past the
                // modal's height ceiling and triggering a RenderFlex
                // bottom-overflow. Capping at one line + ellipsis keeps
                // the header compact regardless of input length.
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Note: Needs to remain as an if statement until packages are upgraded
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
