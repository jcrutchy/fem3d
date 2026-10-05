unit fem_cg_types;

// Material fatigue-crack-growth constants, one record per material, one
// set of constants per growth law it supports. A material need not
// supply constants for every law -- HasXxx flags say which are usable,
// and fem_cg_growthlaws' selection modes (ConservativeRate,
// BestAvailableRate) only consider laws a material actually has data
// for, same "explicit, validated, no silent wrong default" philosophy
// as fem3d's own TMaterial/TProperty (a beam requires nu, a shell
// requires thickness -- this requires whichever law's own constants,
// nothing implied or defaulted).
//
// Units are deliberately NOT fixed by this record -- da/dN, C, and K
// all need to be in a mutually consistent unit system (e.g. metres/
// cycle and MPa*sqrt(m), or inches/cycle and ksi*sqrt(in)), same as
// fem3d's own SI-or-consistent convention (see docs/model_format.md).
// Mixing unit systems between a material's constants and the K values
// passed to fem_cg_growthlaws will not raise an error -- there is no
// way to detect it from the numbers alone -- so getting this right is
// the caller's responsibility, the same way it already is throughout
// fem3d proper.

{$mode objfpc}{$H+}

interface

type
  TCrackGrowthMaterial = record
    Name: string;

    // Paris: da/dN = C * DeltaK^m
    HasParis: Boolean;
    ParisC, ParisM: Double;

    // Walker: da/dN = C * (DeltaK / (1-R)^(1-Gamma))^m
    // Gamma=1 makes this identical to Paris for any R (the (1-R)^0 term
    // vanishes) -- a material can reuse its Paris C, M with a measured
    // Gamma, or fit fresh Walker constants; this record doesn't assume
    // either -- both are separate, explicit fields.
    HasWalker: Boolean;
    WalkerC, WalkerM, WalkerGamma: Double;

    // Forman: da/dN = C * DeltaK^n / ((1-R)*Kc - DeltaK)
    // NOTE: Forman's C is NOT the same constant as Paris' C for the
    // same material, even when n=m -- the extra (1-R)*Kc-DeltaK
    // denominator carries units of K, so Forman's C absorbs a
    // different length-scale factor. Don't reuse ParisC here.
    HasForman: Boolean;
    FormanC, FormanN, FormanKc: Double;

    // NASGRO: da/dN = C * (((1-f)/(1-R)) * DeltaK)^n
    //                   * (1 - DeltaKth/DeltaK)^p / (1 - Kmax/Kc)^q
    // f is Newman's crack-opening-stress ratio (Sop/Smax), a function
    // of R, the ratio of max applied stress to flow stress, and a
    // constraint factor Alpha (1.0 plane stress, 3.0 plane strain) --
    // see fem_cg_growthlaws.NewmanClosureF for the exact form. Flags
    // this closure model as the one genuinely intricate, easy-to-get-
    // subtly-wrong piece of this whole unit: cross-checked here against
    // an independently written Python reference to catch transcription
    // slips, but the closure-model FORM ITSELF (which published NASGRO
    // material datasets assume) is worth an independent check against
    // the actual NASGRO reference manual before this is trusted for
    // real (especially certification-relevant) work -- see
    // docs/TODO_crackgrowth.md.
    HasNasgro: Boolean;
    NasgroC, NasgroN, NasgroP, NasgroQ: Double;
    NasgroDeltaKth, NasgroKc: Double;
    NasgroAlpha: Double;       // constraint factor: 1.0 plane stress, 3.0 plane strain
  end;

implementation

end.
