import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memer/models/callout.dart';
import 'package:memer/models/meme_config.dart';
import 'package:memer/models/meme_controller.dart';

void main() {
  group('MemeConfig', () {
    test('has sensible defaults', () {
      const MemeConfig config = MemeConfig();
      expect(config.topText, '');
      expect(config.bottomText, '');
      expect(config.hasBackgroundImage, isFalse);
      expect(config.callouts, isEmpty);
    });

    test('copyWith can set and clear the background image', () {
      final MemeConfig withImage = const MemeConfig()
          .copyWith(backgroundImage: Uint8List.fromList(<int>[1, 2, 3]));
      expect(withImage.hasBackgroundImage, isTrue);

      final MemeConfig cleared = withImage.copyWith(clearBackgroundImage: true);
      expect(cleared.hasBackgroundImage, isFalse);
    });
  });

  group('Callout', () {
    test('clampedToCanvas keeps the position within 0..1', () {
      const Callout callout = Callout(id: 'a', position: Offset(2, -1));
      final Callout clamped = callout.clampedToCanvas();
      expect(clamped.position.dx, 1.0);
      expect(clamped.position.dy, 0.0);
    });

    test('copyWith preserves id and overrides fields', () {
      const Callout callout = Callout(id: 'x', text: 'hello');
      final Callout updated = callout.copyWith(text: 'bye');
      expect(updated.id, 'x');
      expect(updated.text, 'bye');
    });
  });

  group('MemeController', () {
    test('addCallout adds a bubble and selects it', () {
      final MemeController controller = MemeController();
      expect(controller.config.callouts, isEmpty);

      final String id = controller.addCallout();
      expect(controller.config.callouts.length, 1);
      expect(controller.selectedCalloutId, id);
      expect(controller.selectedCallout, isNotNull);
    });

    test('removeCallout removes it and clears the selection', () {
      final MemeController controller = MemeController();
      final String id = controller.addCallout();
      controller.removeCallout(id);
      expect(controller.config.callouts, isEmpty);
      expect(controller.selectedCalloutId, isNull);
    });

    test('moveCallout clamps the bubble onto the canvas', () {
      final MemeController controller = MemeController();
      final String id = controller.addCallout();
      controller.moveCallout(id, const Offset(5, 5));
      expect(controller.selectedCallout!.position.dx, 1.0);
      expect(controller.selectedCallout!.position.dy, 1.0);
    });

    test('updateCallout edits only the targeted bubble', () {
      final MemeController controller = MemeController();
      final String id1 = controller.addCallout();
      final String id2 = controller.addCallout();

      controller.updateCallout(id1, (Callout c) => c.copyWith(text: 'first'));

      final Callout first =
          controller.config.callouts.firstWhere((Callout c) => c.id == id1);
      final Callout second =
          controller.config.callouts.firstWhere((Callout c) => c.id == id2);
      expect(first.text, 'first');
      expect(second.text, isNot('first'));
    });

    test('notifies listeners when state changes', () {
      final MemeController controller = MemeController();
      int notifications = 0;
      controller.addListener(() => notifications++);

      controller.setTopText('hi');
      controller.setBottomText('bye');
      controller.setBackgroundColor(const Color(0xFF00FF00));

      expect(notifications, 3);
      expect(controller.config.topText, 'hi');
      expect(controller.config.bottomText, 'bye');
      expect(controller.config.backgroundColor, const Color(0xFF00FF00));
    });

    test('header, footnote and link round-trip through the controller', () {
      final MemeController controller = MemeController();
      controller.setHeaderText('via @anshu');
      controller.setHeaderAlign(MemeTextAlign.left);
      controller.setFootnoteText('made with memer');
      controller.setFootnoteAlign(MemeTextAlign.right);
      controller.setLinkUrl('https://example.com');
      controller.setLinkLabel('see more');
      controller.setLinkAlign(MemeTextAlign.right);

      expect(controller.config.headerText, 'via @anshu');
      expect(controller.config.headerAlign, MemeTextAlign.left);
      expect(controller.config.footnoteText, 'made with memer');
      expect(controller.config.footnoteAlign, MemeTextAlign.right);
      expect(controller.config.linkUrl, 'https://example.com');
      expect(controller.config.linkLabel, 'see more');
      expect(controller.config.linkAlign, MemeTextAlign.right);

      expect(controller.config.hasHeader, isTrue);
      expect(controller.config.hasFootnote, isTrue);
      expect(controller.config.hasLink, isTrue);
      expect(controller.config.linkDisplay, 'see more');
    });

    test('linkDisplay falls back to the URL when the label is blank', () {
      const MemeConfig config = MemeConfig(linkUrl: 'https://example.com');
      expect(config.linkDisplay, 'https://example.com');
    });
  });
}
