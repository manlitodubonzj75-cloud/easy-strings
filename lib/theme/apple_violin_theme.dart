import 'package:flutter/material.dart';

/// EASY VIOLIN // Obsidian Design System
///
/// Design tokens ported from the award-level prototype
/// (`easy_violin_mobile_ui.html`), which is the visual source of truth.
///
/// Chromatic discipline (the 90/10 rule): ~90% of the surface area is built
/// from near-black obsidian/graphite layers, and at most 10% is a single
/// high-voltage lime accent. Pure `#000000` backgrounds are intentionally
/// banned to avoid stark clipping.
///
/// The legacy `apple*` names are kept as aliases so existing screens keep
/// compiling, but they are remapped onto the obsidian palette so the whole
/// app adopts the prototype's look.
class AppleViolinTheme {
  // ---------------------------------------------------------------------------
  // Void chromatics — layered obsidian surfaces (never pure black)
  // ---------------------------------------------------------------------------
  static const Color voidBg = Color(0xFF07080A); // root scaffold
  static const Color obsidianCard = Color(0xFF0B0D13); // primary bento fill
  static const Color graphiteElevated = Color(0xFF11141C); // active containers
  static const Color elevatedHigher = Color(0xFF151823); // modals / popovers
  static const Color borderSubtle = Color(0x14FFFFFF); // 8% white hairline
  static const Color borderHover = Color(0x33FFFFFF); // 20% white hairline

  // ---------------------------------------------------------------------------
  // Luminescent accents — the sanctioned 10%
  // ---------------------------------------------------------------------------
  static const Color highVoltageLime = Color(0xFFD4FF00); // pitch lock / in-tune beacon
  static const Color electricCobalt = Color(0xFF2563EB); // secondary state
  static const Color solarAmber = Color(0xFFFF5500); // sharp / above pitch
  static const Color hyperEmerald = Color(0xFF10B981); // success / clean tone
  static const Color crimsonScratch = Color(0xFFFF2A55); // bow-scratch warning

  // ---------------------------------------------------------------------------
  // Typography colors
  // ---------------------------------------------------------------------------
  static const Color headline = Color(0xFFF4F4F5); // zinc-100 headlines
  static const Color subtext = Color(0xFFA1A1AA); // zinc-400 body copy

  // ---------------------------------------------------------------------------
  // String signature colors (open strings G · D · A · E)
  // ---------------------------------------------------------------------------
  static const Color stringG = Color(0xFFA855F7); // purple
  static const Color stringD = Color(0xFF3B82F6); // blue
  static const Color stringA = Color(0xFFD4FF00); // high-voltage lime
  static const Color stringE = Color(0xFFF59E0B); // amber

  // ---------------------------------------------------------------------------
  // Legacy aliases — remapped onto the obsidian palette
  // ---------------------------------------------------------------------------
  static const Color darkBg = voidBg;
  static const Color cardDark = obsidianCard;
  static const Color elevatedDark = graphiteElevated;
  static const Color borderDark = borderSubtle;

  static const Color appleBlue = electricCobalt;
  static const Color appleGreen = hyperEmerald;
  static const Color appleOrange = solarAmber;
  static const Color appleRed = crimsonScratch;
  static const Color appleIndigo = Color(0xFF5856D6);
  static const Color applePurple = stringG;
  static const Color appleTeal = Color(0xFF5AC8FA);
  static const Color appleYellow = Color(0xFFFFCC00);

  // ---------------------------------------------------------------------------
  // Corner radii
  // ---------------------------------------------------------------------------
  static final BorderRadius cardRadius = BorderRadius.circular(20);
  static final BorderRadius bentoRadius = BorderRadius.circular(24);
  static final BorderRadius btnRadius = BorderRadius.circular(14);
  static final BorderRadius pillRadius = BorderRadius.circular(999);

  // ---------------------------------------------------------------------------
  // Motion — cubic-bezier acceleration only (no linear transitions)
  // ---------------------------------------------------------------------------
  static const Duration motionFast = Duration(milliseconds: 280);
  static const Duration motion = Duration(milliseconds: 550);
  static const Curve easeOutExpo = Cubic(0.16, 1, 0.3, 1);

  // ---------------------------------------------------------------------------
  // Shadows — ultra-diffused ambient depth + sub-pixel luminescence
  // ---------------------------------------------------------------------------
  static const BoxShadow softShadow = BoxShadow(
    color: Color(0x66000000), // ~40% black
    blurRadius: 30,
    offset: Offset(0, 15),
  );

  static const BoxShadow blueGlow = BoxShadow(
    color: Color(0x4D2563EB), // cobalt
    blurRadius: 24,
    spreadRadius: 1,
  );

  static const BoxShadow greenGlow = BoxShadow(
    color: Color(0x33D4FF00), // high-voltage lime
    blurRadius: 24,
    spreadRadius: 1,
  );

  static const BoxShadow limeGlow = BoxShadow(
    color: Color(0x40D4FF00),
    blurRadius: 24,
    spreadRadius: 2,
  );

  // ---------------------------------------------------------------------------
  // Typefaces
  //
  // NOTE: these families only render if the corresponding font files are
  // bundled as Flutter assets (or sourced via the `google_fonts` package).
  // Until then Flutter falls back to the platform default, so treat these as
  // the intended families rather than guaranteed output.
  // ---------------------------------------------------------------------------
  static const String fontSans = 'Plus Jakarta Sans';
  static const String fontDisplay = 'Syne';
  static const String fontEditorial = 'Playfair Display';
  static const String fontMono = 'JetBrains Mono';

  /// Monospaced uppercase micro-telemetry (badges, timestamps, reads states).
  static const TextStyle telemetry = TextStyle(
    fontFamily: fontMono,
    fontSize: 10,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    color: subtext,
  );

  // ---------------------------------------------------------------------------
  // Container / control decorations
  // ---------------------------------------------------------------------------

  /// Sub-pixel glass container: translucent gradient fill, hairline border and
  /// volumetric ambient shadow. Mirrors the prototype's `.glass-card`.
  ///
  /// For a true frosted look, wrap the child in a `BackdropFilter`; a
  /// `BoxDecoration` alone cannot blur the backdrop.
  static BoxDecoration glassDecoration({
    bool highlighted = false,
    BorderRadius? radius,
  }) {
    return BoxDecoration(
      borderRadius: radius ?? bentoRadius,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x0BFFFFFF), Color(0x02FFFFFF), Color(0x05FFFFFF)],
        stops: [0.0, 0.55, 1.0],
      ),
      border: Border.all(
        color: highlighted ? borderHover : borderSubtle,
        width: 1.0,
      ),
      boxShadow: [
        const BoxShadow(
          color: Color(0xE6000000),
          blurRadius: 60,
          spreadRadius: -30,
          offset: Offset(0, 24),
        ),
        const BoxShadow(
          color: Color(0x0FFFFFFF),
          blurRadius: 1,
          offset: Offset(0, 1),
        ),
        if (highlighted)
          const BoxShadow(
            color: Color(0x1FD4FF00),
            blurRadius: 24,
            spreadRadius: 2,
          ),
      ],
    );
  }

  /// Primary CTA: stark white pill with diffuse luminescence.
  static BoxDecoration primaryCtaDecoration({BorderRadius? radius}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: radius ?? pillRadius,
      boxShadow: const [
        BoxShadow(
          color: Color(0x73FFFFFF),
          blurRadius: 34,
          spreadRadius: -12,
          offset: Offset(0, 12),
        ),
      ],
    );
  }

  /// Secondary CTA: glass pill with hairline border.
  static BoxDecoration glassCtaDecoration({BorderRadius? radius}) {
    return BoxDecoration(
      color: const Color(0x0AFFFFFF),
      borderRadius: radius ?? btnRadius,
      border: Border.all(color: const Color(0x1AFFFFFF)),
    );
  }
}
