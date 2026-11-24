import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nivio/core/app_platform.dart';

class SettingsPageHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const SettingsPageHeader(
    this.title, {
    super.key,
    this.onBack,
    this.titleTextStyle,
  });

  final String title;
  final VoidCallback? onBack;
  final TextStyle? titleTextStyle;

  double get _topSpacing {
    final platform = defaultTargetPlatform;
    return !AppPlatform.isTv &&
            (platform == TargetPlatform.android ||
                platform == TargetPlatform.iOS)
        ? 24
        : 0;
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + _topSpacing);

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    final appBar = AppBar(
      primary: false,
      toolbarHeight: kToolbarHeight,
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      title: Text(title),
      titleTextStyle: titleTextStyle,
      leading: onBack == null ? null : BackButton(onPressed: onBack),
    );
    return ColoredBox(
      color: background,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(top: _topSpacing),
          child: appBar,
        ),
      ),
    );
  }
}
