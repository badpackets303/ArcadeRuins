//  The four rows of sections (P6, ADR-045).
//
//  Each row takes the controls of one or two classic panels and re-homes them. The
//  grouping follows the design canvas the owner approved on 2026-09-12:
//
//    1. OSC 1 · OSC 2 · Mix · Filter · Voice · Master        (the Generators panel)
//    2. Filter Envelope · Amplitude Envelope · LFO & targets (Envelopes + half of Effects)
//    3. Reverb · Delay · Phaser · Bitcrusher & Auto Pan      (the other half of Effects)
//    4. Arpeggiator / Sequencer · XY Pads                    (Sequencer + Touch Pad)
//
//  Sizes are the canvas's: 42-point knobs on the main row, a 54-point cutoff, 36 for the
//  envelopes and the mix, 38 for the effects, 28–32 for the LFOs and the sequencer's
//  own controls. Every knob is above Apple's 28-point macOS hit-region guidance.

import UIKit

extension S1DesktopLayout {

    // P8-0: 158 fits a 36-point selector over a 44-point knob with its two readouts; 220 fits two
    // LFO lines of 30-point knobs over two lines of 22-point chips. Row four takes the rest: 247
    // at 900 tall, about 84 points of fader travel.
    private var rowHeights: (generators: CGFloat, envelopes: CGFloat, effects: CGFloat) { (158, 220, 122) }

    /// P7-9 (ADR-059): a template's frames are smaller than the rows' own — the painting gives a
    /// sixth of the window to the cabinet — so the three tightest sections draw a size down.
    private var isCompact: Bool { skin.template != nil }

    func buildRows() {
        let rows = [generatorsRow(), envelopesRow(), effectsRow(), sequencerRow()]
        rows.forEach { editor.addArrangedSubview($0) }
        NSLayoutConstraint.activate([
            rows[0].heightAnchor.constraint(equalToConstant: rowHeights.generators),
            rows[1].heightAnchor.constraint(equalToConstant: rowHeights.envelopes),
            rows[2].heightAnchor.constraint(equalToConstant: rowHeights.effects)
        ])
    }

    // MARK: - Row helpers

    private func row(_ views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fill
        stack.spacing = S1DesktopTheme.rowGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func section(_ title: String, key: String? = nil, width: CGFloat? = nil) -> S1SectionView {
        let section = S1SectionView(title: title)
        if let width { section.widthAnchor.constraint(equalToConstant: width).isActive = true }
        section.accent = S1Skins.current.sectionAccent(for: key ?? title)   // P7-4: the skin's word, by key
        sections[key ?? title] = section
        return section
    }

    private func knobCell(_ knob: Knob, _ title: String, _ size: CGFloat, _ format: S1ValueFormat,
                          from panel: UIViewController) -> S1ControlCell {
        move(knob, into: nil)
        remember(knob, from: panel)
        return S1ControlCell(control: knob, title: title, size: CGSize(width: size, height: size), format: format)
    }

    private func switchCell(_ toggle: ToggleButton, _ title: String, from panel: UIViewController) -> S1SwitchCell {
        move(toggle, into: nil)
        remember(toggle, from: panel)
        return S1SwitchCell(toggle: toggle, title: title)
    }

    private func verticalBody(_ section: S1SectionView, spacing: CGFloat = 6) {
        section.body.axis = .vertical
        section.body.alignment = .fill
        section.body.distribution = .fill
        section.body.spacing = spacing
    }

    /// A view on a line of its own, centred, for a body that otherwise fills.
    private func centred(_ view: UIView) -> UIStackView {
        let line = UIStackView(arrangedSubviews: [flexibleSpace(), view, flexibleSpace()])
        line.axis = .horizontal
        line.alignment = .center
        return line
    }

    private func knobRow(_ cells: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: cells)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalCentering
        stack.spacing = 6
        return stack
    }

    private func caption(_ text: String, size: CGFloat = 11, colour: UIColor = S1DesktopTheme.dim) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = S1DesktopTheme.font(size)
        label.textColor = colour
        label.textAlignment = .center
        return label
    }

    // MARK: - Row 1: generators

    private func generatorsRow() -> UIStackView {
        let g = manager.generatorsPanel
        // Row one: OSC 1 · OSC 2 · Mix (flexible) · Filter · Voice. Master lives in the effects row.

        // P8-0: the sidebar is gone and the row has the whole 1440 (owner, 2026-09-13: "more
        // wiggle room"). The fixed sections grew — wider selectors, 44-point knobs — and Mix
        // still has about 560 points for its seven.
        let oscKnob: CGFloat = isCompact ? 36 : 44
        let osc1 = section("OSC 1", width: 184)   // 152 selector + 2 × 14 margin, with 4 to spare
        verticalBody(osc1, spacing: isCompact ? 3 : 8)
        osc1.body.alignment = .center
        move(g.morph1Selector, into: nil); remember(g.morph1Selector, from: g)
        sized(g.morph1Selector, width: isCompact ? 136 : 152, height: isCompact ? 30 : 36)
        osc1.add(g.morph1Selector)
        osc1.add(knobCell(g.morph1SemitoneOffset, "Semitones", oscKnob, .semitones, from: g))

        let osc2 = section("OSC 2", width: 204)   // 172 selector + 2 × 14 margin, with 4 to spare
        verticalBody(osc2, spacing: isCompact ? 3 : 8)
        move(g.morph2Selector, into: nil); remember(g.morph2Selector, from: g)
        sized(g.morph2Selector, width: isCompact ? 148 : 172, height: isCompact ? 30 : 36)
        osc2.add(centred(g.morph2Selector))
        // P8-1: the two knobs each take half the width, so they sit apart (owner: "scrunched
        // together"); the body fills, and the selector is centred on its own line above.
        let osc2Knobs = knobRow([knobCell(g.morph2SemitoneOffset, "Semitones", oscKnob, .semitones, from: g),
                                 knobCell(g.morph2Detuning, "Detune", oscKnob, .decimal, from: g)])
        osc2Knobs.distribution = .fillEqually
        osc2.add(osc2Knobs)

        // The one flexible section of the row. Master moved to the effects row (owner,
        // 2026-09-12) so the seven knobs here have room.
        let mix = section("Mix")
        mix.body.layoutMargins = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        mix.addHeaderAccessory(switchCell(g.subOctaveDown, "Sub −24", from: g))
        mix.addHeaderAccessory(switchCell(g.subIsSquare, "Sub square", from: g))
        mix.add(knobCell(g.subVolume, "Sub", 52, .percent, from: g))
        mix.add(knobCell(g.morph1Volume, "OSC 1", 52, .percent, from: g))
        mix.add(knobCell(g.morph2Volume, "OSC 2", 52, .percent, from: g))
        mix.add(knobCell(g.morphBalance, "Blend", 52, .percent, from: g))
        mix.add(knobCell(g.fmVolume, "FM", 52, .percent, from: g))
        mix.add(knobCell(g.fmAmount, "FM Mod", 52, .decimal, from: g))
        mix.add(knobCell(g.noiseVolume, "Noise", 52, .percent, from: g))

        let filter = section("Filter", width: 240)   // P8-1: a 68-point cutoff and two 52s
        // The classic cycling button stays where it is, hidden and bound; the picker in the
        // header drives it and follows `.filterType` (P6-2).
        filter.addHeaderAccessory(makeFilterPicker(for: g.filterTypeToggle))
        filter.body.layoutMargins = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        filter.add(knobCell(g.cutoff, "Cutoff", 68, .hertz, from: g))
        filter.add(knobCell(g.resonance, "Resonance", 52, .decimal, from: g))
        let e = manager.envelopesPanel
        filter.add(knobCell(e.filterADSRMixKnob, "Env Amt", 52, .percent, from: e))
        // The classic panel renames the cutoff and resonance captions by filter type;
        // it still does, on labels that are no longer shown. The header display strip
        // carries the type.

        let voice = section("Voice", width: 156)
        if isCompact {
            // The painted frame is 120 points wide: the switches go under the knob, not beside it
            verticalBody(voice, spacing: 2)
            voice.body.alignment = .center
            voice.body.layoutMargins = UIEdgeInsets(top: 0, left: 6, bottom: 2, right: 6)
        }
        voice.add(knobCell(g.glideKnob, "Glide", isCompact ? 34 : 52, .decimal, from: g))
        voice.add(S1SwitchColumn([switchCell(g.isMonoToggle, "Mono", from: g),
                                  switchCell(g.legatoModeToggle, "Legato", from: g)]))

        return row([osc1, osc2, mix, filter, voice])
    }

    // MARK: - Row 2: envelopes and LFOs

    private func envelopesRow() -> UIStackView {
        let e = manager.envelopesPanel
        let fx = manager.fxPanel

        let envelopeKnob: CGFloat = isCompact ? 38 : 46
        let filterEnvelope = section("Filter Envelope")
        verticalBody(filterEnvelope)
        filterEnvelope.body.layoutMargins = UIEdgeInsets(top: isCompact ? 4 : 8, left: 12, bottom: isCompact ? 2 : 6, right: 12)
        plot(e.filterADSRView, in: filterEnvelope)
        filterEnvelope.add(knobRow([knobCell(e.filterAttackKnob, "Attack", envelopeKnob, .seconds, from: e),
                                    knobCell(e.filterDecayKnob, "Decay", envelopeKnob, .seconds, from: e),
                                    knobCell(e.filterSustainKnob, "Sustain", envelopeKnob, .percent, from: e),
                                    knobCell(e.filterReleaseKnob, "Release", envelopeKnob, .seconds, from: e)]))

        let amplitudeEnvelope = section("Amplitude Envelope")
        verticalBody(amplitudeEnvelope)
        amplitudeEnvelope.body.layoutMargins = UIEdgeInsets(top: isCompact ? 4 : 8, left: 12, bottom: isCompact ? 2 : 6, right: 12)
        plot(e.adsrView, in: amplitudeEnvelope)
        amplitudeEnvelope.add(knobRow([knobCell(e.attackKnob, "Attack", envelopeKnob, .seconds, from: e),
                                       knobCell(e.decayKnob, "Decay", envelopeKnob, .seconds, from: e),
                                       knobCell(e.sustainKnob, "Sustain", envelopeKnob, .percent, from: e),
                                       knobCell(e.releaseKnob, "Release", envelopeKnob, .seconds, from: e),
                                       knobCell(e.adsrPitchTrackingKnob, "Pitch Track", envelopeKnob, .decimal, from: e)]))

        // P8-1 (owner: "clunky and haphazard, with the 4 tiny knobs scrunched up on the right"):
        // two columns. Left, the two LFOs — name, wave picker, rate and amount, 40-point knobs
        // beside their picker. Right, the twelve targets as a 3 × 4 grid.
        let lfo = section("LFO & Mod Targets")
        lfo.body.alignment = .center
        lfo.body.distribution = .fill
        lfo.body.spacing = 12
        lfo.body.layoutMargins = UIEdgeInsets(top: isCompact ? 0 : 4, left: isCompact ? 6 : 12, bottom: isCompact ? 0 : 4, right: isCompact ? 6 : 12)
        if isCompact { lfo.body.spacing = 4 }
        lfo.addHeaderAccessory(switchCell(fx.tempoSyncToggle, "Tempo sync", from: fx))
        let lfos = UIStackView(arrangedSubviews: [
            lfoLine("LFO 1", picker: fx.lfo1WavePicker, rate: fx.lfo1RateKnob, amount: fx.lfo1AmpKnob,
                    rateFormat: rateFormat(.lfo1Rate, kind: .frequency), from: fx),
            lfoLine("LFO 2", picker: fx.lfo2WavePicker, rate: fx.lfo2RateKnob, amount: fx.lfo2AmpKnob,
                    rateFormat: rateFormat(.lfo2Rate, kind: .frequency), from: fx)
        ])
        lfos.axis = .vertical
        lfos.alignment = .leading
        lfos.spacing = isCompact ? 0 : 6
        lfo.add(lfos)
        lfo.add(flexibleSpace())
        let targets: [LFOToggle] = [fx.cutoffLFOToggle, fx.resonanceLFOToggle, fx.oscMixLFOToggle, fx.reverbMixLFOToggle,
                                    fx.decayLFOToggle, fx.noiseLFOToggle, fx.fmModLFOToggle, fx.detuneLFOToggle,
                                    fx.filterEnvLFOToggle, fx.pitchLFOToggle, fx.bitcrushLFOToggle, fx.tremoloLFOToggle]
        let grid = UIStackView(arrangedSubviews: stride(from: 0, to: 12, by: 3).map { start in
            let line = UIStackView(arrangedSubviews: targets[start..<start + 3].map { toggle in
                move(toggle, into: nil); remember(toggle, from: fx)
                toggle.drawsDesktopStyle = true
                sized(toggle, width: isCompact ? 52 : 66, height: 22)
                return toggle
            })
            line.axis = .horizontal
            line.spacing = 4
            return line
        })
        grid.axis = .vertical
        grid.spacing = 4
        lfo.add(grid)

        let stack = row([filterEnvelope, amplitudeEnvelope, lfo])
        NSLayoutConstraint.activate([
            amplitudeEnvelope.widthAnchor.constraint(equalTo: filterEnvelope.widthAnchor, multiplier: 1.15),
            lfo.widthAnchor.constraint(equalTo: filterEnvelope.widthAnchor, multiplier: 1.25)   // P8-1: the LFO lines beside the target grid
        ])
        return stack
    }

    private func plot(_ view: AKADSRView, in section: S1SectionView) {
        move(view, into: nil)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.heightAnchor.constraint(equalToConstant: isCompact ? 36 : 54).isActive = true
        view.layer.cornerRadius = 4
        view.layer.borderWidth = 1
        view.layer.borderColor = S1DesktopTheme.plotBorder.cgColor
        view.layer.masksToBounds = true
        // P7-4 (ADR-048): under a skin that gives the section an accent, the curve and its
        // fill take it; the storyboard's orange stays under the others. Which envelope has a
        // fill at all is the storyboard's word (the filter envelope's is clear).
        if let accent = section.accent {
            view.curveColor = accent.mixed(with: .white, 0.4)
            for keyPath in [\AKADSRView.attackColor, \AKADSRView.decayColor, \AKADSRView.sustainColor, \AKADSRView.releaseColor]
            where view[keyPath: keyPath].cgColor.alpha > 0 {
                view[keyPath: keyPath] = accent.withAlphaComponent(0.5)
            }
        }
        section.add(view)
    }

    private func lfoLine(_ name: String, picker: LFOWavePicker, rate: Knob, amount: Knob,
                         rateFormat: S1ValueFormat, from panel: UIViewController) -> UIStackView {
        let label = caption(name)
        label.widthAnchor.constraint(equalToConstant: 34).isActive = true
        label.textAlignment = .left
        move(picker, into: nil); remember(picker, from: panel)
        picker.drawsDesktopStyle = true
        sized(picker, width: isCompact ? 88 : 112, height: isCompact ? 24 : 26)
        let knob: CGFloat = isCompact ? 28 : 40
        let rateCell = knobCell(rate, "Rate", knob, rateFormat, from: panel)
        rateCells.append(rateCell)
        let amountCell = knobCell(amount, "Amount", knob, .percent, from: panel)
        // Fixed widths, so a readout that changes length moves nothing
        [rateCell, amountCell].forEach { $0.fixWidth(isCompact ? 54 : 64) }
        var leading: [UIView] = [label, picker]
        if isCompact {
            // The name goes over its picker: the frame has no width for it beside
            let named = UIStackView(arrangedSubviews: [label, picker])
            named.axis = .vertical
            named.alignment = .leading
            named.spacing = 2
            [rateCell, amountCell].forEach { $0.spacing = 0 }
            leading = [named]
        }
        let line = UIStackView(arrangedSubviews: leading + [rateCell, amountCell])
        line.axis = .horizontal
        line.alignment = .center
        line.spacing = 10
        if isCompact { line.setCustomSpacing(14, after: leading[0]) }   // the knobs a notch right of the picker
        return line
    }

    // MARK: - Row 3: effects

    private func effectsRow() -> UIStackView {
        let fx = manager.fxPanel

        let reverb = section("Reverb")
        reverb.addHeaderAccessory(switchCell(fx.reverbToggle, "On", from: fx))
        reverb.add(knobCell(fx.reverbSizeKnob, "Size", 48, .percent, from: fx))
        reverb.add(knobCell(fx.reverbLowCutKnob, "Low Cut", 48, .hertz, from: fx))
        reverb.add(knobCell(fx.reverbMixKnob, "Mix", 48, .percent, from: fx))

        let delay = section("Delay")
        delay.addHeaderAccessory(switchCell(fx.delayToggle, "On", from: fx))
        let delayTime = knobCell(fx.delayTimeKnob, "Time", 48, rateFormat(.delayTime, kind: .time), from: fx)
        rateCells.append(delayTime)
        delay.add(delayTime)
        delay.add(knobCell(fx.delayFeedbackKnob, "Feedback", 48, .percent, from: fx))
        delay.add(knobCell(fx.delayMixKnob, "Mix", 48, .percent, from: fx))

        let phaser = section("Phaser")
        phaser.add(knobCell(fx.phaserRateKnob, "Rate", 48, .decimal, from: fx))
        phaser.add(knobCell(fx.phaserNotchWidthKnob, "Notch", 48, .decimal, from: fx))
        phaser.add(knobCell(fx.phaserFeedbackKnob, "Feedback", 48, .decimal, from: fx))
        phaser.add(knobCell(fx.phaserMixKnob, "Mix", 48, .decimal, from: fx))

        let crush = section("Bitcrusher & Auto Pan", key: "Bitcrusher")
        crush.add(knobCell(fx.sampleRateKnob, "Bitrate", 48, .hertz, from: fx))
        crush.add(knobCell(fx.autoPanAmountKnob, "Pan Amt", 48, .percent, from: fx))
        let panRate = knobCell(fx.autoPanRateKnob, "Pan Rate", 48, rateFormat(.autoPanFrequency, kind: .frequency), from: fx)
        rateCells.append(panRate)
        crush.add(panRate)

        // Master: the output stage, at the end of the effects chain (moved from row one at the
        // owner's request, 2026-09-12, to give Mix its room).
        let g = manager.generatorsPanel
        let master = section("Master", width: 172)
        master.add(knobCell(g.masterVolume, "Volume", 48, .percent, from: g))
        master.add(S1SwitchColumn([switchCell(g.oscBandlimitEnable, "Anti-alias", from: g),
                                   switchCell(g.widenToggle, "Widen", from: g),
                                   switchCell(g.sequencerToggle, "Arp / Seq", from: g)]))

        let stack = row([reverb, delay, phaser, crush, master])
        NSLayoutConstraint.activate([
            delay.widthAnchor.constraint(equalTo: reverb.widthAnchor, multiplier: 1.1),
            phaser.widthAnchor.constraint(equalTo: reverb.widthAnchor, multiplier: 1.3),
            crush.widthAnchor.constraint(equalTo: reverb.widthAnchor)
        ])
        return stack
    }

    // MARK: - Row 4: sequencer and pads

    private func sequencerRow() -> UIStackView {
        let seq = manager.sequencerPanel
        let g = manager.generatorsPanel
        let pads = manager.touchPadPanel

        let sequencer = section("Arpeggiator / Sequencer", key: "Sequencer")
        verticalBody(sequencer, spacing: 8)
        sequencer.body.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        let transport = caption(NSLocalizedString("Following host transport", comment: "Sequencer header"))
        transport.isHidden = !manager.conductor.isHosted
        sequencer.addHeaderAccessory(transport)

        // Controls line (P6-3: every control in the desktop dress, hit zones following the bounds)
        move(seq.sequencerToggle, into: nil); remember(seq.sequencerToggle, from: seq)
        seq.sequencerToggle.desktopLabels = ("Arp", "Seq")
        seq.sequencerToggle.drawsDesktopStyle = true
        sized(seq.sequencerToggle, width: 76, height: 24)
        move(seq.arpDirectionButton, into: nil); remember(seq.arpDirectionButton, from: seq)
        seq.arpDirectionButton.drawsDesktopStyle = true
        sized(seq.arpDirectionButton, width: 96, height: 24)
        move(seq.octaveStepper, into: nil); remember(seq.octaveStepper, from: seq)
        seq.octaveStepper.drawsDesktopStyle = true
        sized(seq.octaveStepper, width: 96, height: 24)
        move(seq.seqStepsStepper, into: nil); remember(seq.seqStepsStepper, from: seq)
        seq.seqStepsStepper.drawsDesktopStyle = true
        sized(seq.seqStepsStepper, width: 96, height: 24)
        move(g.tempoStepper, into: nil); remember(g.tempoStepper, from: g)
        g.tempoStepper.drawsDesktopStyle = true
        sized(g.tempoStepper, width: 84, height: 50)

        let controls = UIStackView(arrangedSubviews: [
            switchCell(seq.arpToggle, "On", from: seq),
            labelled("Arp / Seq", seq.sequencerToggle),
            knobCell(seq.arpInterval, "Interval", 30, .integer(unit: ""), from: seq),
            labelled("Direction", seq.arpDirectionButton),
            labelled("Octaves", seq.octaveStepper),
            labelled("Steps", seq.seqStepsStepper),
            knobCell(seq.arpSeqTempoMultiplier, "Div", 30, .custom { "\(Rate.fromFactor($0))" }, from: seq),
            labelled("Tempo", g.tempoStepper)
        ])
        controls.axis = .horizontal
        controls.alignment = .center
        controls.distribution = .equalSpacing
        controls.spacing = 12
        sequencer.add(controls)

        // Sixteen steps: number, slider, on/off
        let steps = UIStackView(arrangedSubviews: (0..<16).map { i -> UIView in
            let number = seq.octBoostButtons[i]
            let slider = seq.sliders[i]
            let on = seq.noteOnButtons[i]
            for view in [number, slider, on] as [UIView] { move(view, into: nil); remember(view, from: seq) }
            number.drawsDesktopStyle = true
            slider.drawsDesktopStyle = true
            on.drawsDesktopStyle = true
            sized(number, width: 40, height: 20)
            slider.widthAnchor.constraint(equalToConstant: 40).isActive = true
            slider.setContentHuggingPriority(.defaultLow, for: .vertical)
            sized(on, width: 40, height: 12)
            let column = UIStackView(arrangedSubviews: [number, slider, on])
            column.axis = .vertical
            column.alignment = .center
            column.spacing = 4
            return column
        })
        steps.axis = .horizontal
        steps.alignment = .fill
        steps.distribution = .equalSpacing
        steps.setContentHuggingPriority(.defaultLow, for: .vertical)
        sequencer.add(steps)

        let padsSection = section("XY Pads", key: "Pads", width: 400)   // P8-0: was 330 beside the sidebar
        padsSection.body.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 6, right: 12)
        padsSection.body.distribution = .fillEqually
        padsSection.body.alignment = .fill
        padsSection.body.spacing = 12
        move(pads.snapToggle, into: nil); remember(pads.snapToggle, from: pads)
        restyle(button: pads.snapToggle, width: 48)
        padsSection.addHeaderAccessory(pads.snapToggle)
        padsSection.add(padColumn(pads.touchPad1, x: "LFO 1 Rate →", y: "↑ LFO 1 Amp", from: pads))
        padsSection.add(padColumn(pads.touchPad2, x: "Filter Cutoff →", y: "↑ Resonance", from: pads))

        return row([sequencer, padsSection])
    }

    /// How a tempo-syncable rate reads: the nearest musical rate when tempo sync is on, as
    /// the header's display strip shows it; Hz or seconds otherwise. Reads the synth, because
    /// these knobs hold a normalised 0…1 position (they are dependent parameters), not the rate.
    enum RateKind { case frequency, time }

    private func rateFormat(_ parameter: S1Parameter, kind: RateKind) -> S1ValueFormat {
        let conductor = manager.conductor
        return .custom { _ in
            guard let synth = conductor.synth else { return "" }
            let value = synth.getSynthParameter(parameter)
            if synth.getSynthParameter(.tempoSyncToArpRate) > 0 {
                switch kind {
                case .frequency: return "\(Rate.fromFrequency(value))"
                case .time: return "\(Rate.fromTime(value))"
                }
            }
            switch kind {
            case .frequency: return S1ValueFormat.hertz.string(for: value)
            case .time: return S1ValueFormat.seconds.string(for: value)
            }
        }
    }

    private func labelled(_ title: String, _ control: UIView) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: [control, caption(title, size: 12, colour: S1DesktopTheme.label)])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 3
        return stack
    }

    private func padColumn(_ pad: AKTouchPadView, x: String, y: String, from panel: UIViewController) -> UIStackView {
        move(pad, into: nil); remember(pad, from: panel)
        pad.layer.cornerRadius = 4
        pad.layer.borderWidth = 1
        pad.layer.borderColor = S1DesktopTheme.plotBorder.cgColor
        pad.layer.masksToBounds = true
        pad.setContentHuggingPriority(.defaultLow, for: .vertical)
        let yLabel = caption(y)
        yLabel.textAlignment = .left
        // P7: a skin may frame the pad as a screen
        let screen: UIView = S1Skins.current.frameAccent.map { S1CRTFrame(content: pad, accent: $0, cornerRadius: 4) } ?? pad
        let column = UIStackView(arrangedSubviews: [yLabel, screen, caption(x)])
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = 3
        return column
    }
}
