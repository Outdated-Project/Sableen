import 'package:material_ui/material_ui.dart';

Future<T?> showPlayerSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required bool rotated,
}) {
  if (!rotated) {
    return showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: builder,
    );
  }
  // The Navigator overlay is outside the locally rotated player on locked phones.
  return showDialog<T>(
    context: context,
    builder: (context) => RotatedBox(
      quarterTurns: MediaQuery.orientationOf(context) == Orientation.portrait
          ? 1
          : 0,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: builder(context),
        ),
      ),
    ),
  );
}
