import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

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
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.sheetHandle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
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
