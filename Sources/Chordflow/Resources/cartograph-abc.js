(function (global) {
  "use strict";

  const scores = new WeakMap();
  let editedSelection = null;

  function message(error) {
    return error && error.message ? error.message : String(error);
  }

  const audio = {
    context: null,
    voices: new Set(),
    highlightTimers: new Set(),
    highlightedElements: new Set(),
    loopTimer: null,

    stop() {
      if (this.loopTimer !== null) global.clearTimeout(this.loopTimer);
      this.loopTimer = null;
      this.voices.forEach(voice => {
        try { voice.stop(); } catch (_) {}
      });
      this.voices.clear();
      this.highlightTimers.forEach(timer => global.clearTimeout(timer));
      this.highlightTimers.clear();
      this.highlightedElements.forEach(element => element.classList.remove("cartograph-abc-playing"));
      this.highlightedElements.clear();
    },

    async activate() {
      const AudioContext = global.AudioContext || global.webkitAudioContext;
      if (!AudioContext) throw new Error("Dieses System unterstützt keine Audiowiedergabe.");
      this.context ||= new AudioContext();
      if (this.context.state === "suspended") await this.context.resume();
    },

    async play(notes, normalizeStart) {
      this.stop();
      if (!notes.length) return;
      await this.activate();

      this.schedule(notes, normalizeStart);
    },

    async loop(notes) {
      this.stop();
      if (!notes.length) return;
      await this.activate();

      const offset = Math.min(...notes.map(note => note.start));
      const duration = Math.max(...notes.map(note => note.start - offset + note.duration));
      const scheduleCycle = () => {
        this.schedule(notes, true);
        this.loopTimer = global.setTimeout(scheduleCycle, Math.max(80, duration * 1000));
      };
      scheduleCycle();
    },

    schedule(notes, normalizeStart) {
      const offset = normalizeStart ? Math.min(...notes.map(note => note.start)) : 0;
      const start = this.context.currentTime + 0.04;
      notes.forEach(note => {
        const noteStart = start + note.start - offset;
        note.pitches.forEach(pitch => this.playTone(pitch, noteStart, note.duration));
        this.highlight(note, noteStart, note.duration);
      });
    },

    highlight(note, start, duration) {
      if (!note.elements.length) return;
      const delay = Math.max(0, (start - this.context.currentTime) * 1000);
      const startTimer = global.setTimeout(() => {
        this.highlightTimers.delete(startTimer);
        note.elements.forEach(element => {
          element.classList.add("cartograph-abc-playing");
          this.highlightedElements.add(element);
        });
        const endTimer = global.setTimeout(() => {
          this.highlightTimers.delete(endTimer);
          note.elements.forEach(element => {
            element.classList.remove("cartograph-abc-playing");
            this.highlightedElements.delete(element);
          });
        }, duration * 1000);
        this.highlightTimers.add(endTimer);
      }, delay);
      this.highlightTimers.add(startTimer);
    },

    playTone(midi, start, duration) {
      const oscillator = this.context.createOscillator();
      const gain = this.context.createGain();
      oscillator.type = "triangle";
      oscillator.frequency.value = 440 * Math.pow(2, (midi - 69) / 12);
      gain.gain.setValueAtTime(0.0001, start);
      gain.gain.exponentialRampToValueAtTime(0.11, start + 0.012);
      gain.gain.exponentialRampToValueAtTime(0.0001, start + duration);
      oscillator.connect(gain);
      gain.connect(this.context.destination);
      oscillator.addEventListener("ended", () => this.voices.delete(oscillator), { once: true });
      oscillator.start(start);
      oscillator.stop(start + duration + 0.02);
      this.voices.add(oscillator);
    }
  };

  function accidentalOffset(accidental) {
    return { dblflat: -2, flat: -1, natural: 0, sharp: 1, dblsharp: 2 }[accidental] || 0;
  }

  function midiPitch(pitch, accidental) {
    const degree = ((pitch % 7) + 7) % 7;
    return 60 + Math.floor(pitch / 7) * 12 + [0, 2, 4, 5, 7, 9, 11][degree] + accidental;
  }

  function playableSequence(tune) {
    const notes = [];
    const measures = [];
    const elementNotes = new Map();

    ABCJS.synth.sequence(tune, {}).forEach((track, trackIndex) => {
      let qpm = 120;
      let measure = 0;
      let noteIndex = 0;
      let key = {};
      let accidentals = {};
      track.forEach(event => {
        if (event.el_type === "tempo") qpm = event.qpm || qpm;
        if (event.el_type === "key") {
          key = Object.fromEntries((event.accidentals || []).map(item => [item.note.toLowerCase(), accidentalOffset(item.acc)]));
          accidentals = {};
        }
        if (event.el_type === "bar") {
          measure += 1;
          accidentals = {};
        }
        if (event.el_type !== "note" || !event.pitches) return;

        const pitches = event.pitches.map(item => {
          const letter = item.name.replace(/[^A-Ga-g]/g, "").toLowerCase();
          const accidentalKey = `${item.pitch}`;
          if (item.accidental) accidentals[accidentalKey] = accidentalOffset(item.accidental);
          return midiPitch(item.pitch, accidentals[accidentalKey] ?? key[letter] ?? 0);
        });
        const note = {
          pitches,
          start: event.timing * 240 / qpm,
          duration: Math.max(0.08, event.duration * 240 / qpm),
          measure,
          trackIndex,
          noteIndex: noteIndex++,
          elements: Array.from(event.elem?.abselem?.elemset || []).filter(Boolean)
        };
        notes.push(note);
        measures[measure] ||= [];
        measures[measure].push(note);
        if (event.elem) elementNotes.set(event.elem, note);
      });
    });
    return { notes, measures, elementNotes };
  }

  function isSingleChordSequence(sequence) {
    if (!sequence.notes.length) return false;
    const first = sequence.notes[0];
    return sequence.notes.every(note => note.start === first.start && note.duration === first.duration)
      && sequence.notes.reduce((count, note) => count + note.pitches.length, 0) > 1;
  }

  function pitchIndexFor(element, analysis) {
    const pitches = element?.pitches || [];
    if (pitches.length < 2) return 0;
    const staffPosition = Number(analysis?.staffPos);
    if (!Number.isFinite(staffPosition)) return 0;
    let best = 0;
    for (let index = 1; index < pitches.length; index++) {
      if (Math.abs(pitches[index].pitch - staffPosition) < Math.abs(pitches[best].pitch - staffPosition)) best = index;
    }
    return best;
  }

  function showEditedSelection(selection) {
    document.querySelectorAll(".cartograph-abc-edit-selected").forEach(element => element.classList.remove("cartograph-abc-edit-selected"));
    const note = score().sequence.notes.find(candidate => candidate.trackIndex === selection.trackIndex && candidate.noteIndex === selection.noteIndex);
    if (!note) return false;
    note.elements.forEach(element => element.classList.add("cartograph-abc-edit-selected"));
    editedSelection = { ...selection, midi: note.pitches[selection.pitchIndex] ?? selection.midi };
    return true;
  }

  function showPitchSelection(midi) {
    const target = Number(midi);
    for (const note of score().sequence.notes) {
      const pitchIndex = note.pitches.indexOf(target);
      if (pitchIndex < 0) continue;
      return showEditedSelection({
        trackIndex: note.trackIndex,
        noteIndex: note.noteIndex,
        measure: note.measure,
        pitchIndex,
        midi: target
      });
    }
    return false;
  }

  function setEditedSelectionColor(color) {
    document.documentElement.style.setProperty("--cartograph-edit-color", String(color));
    return true;
  }

  async function selectEditableNote(element, analysis) {
    const note = score().sequence.elementNotes.get(element);
    if (!note) return;
    const pitchIndex = Math.min(pitchIndexFor(element, analysis), note.pitches.length - 1);
    const selection = { trackIndex: note.trackIndex, noteIndex: note.noteIndex, measure: note.measure, pitchIndex, midi: note.pitches[pitchIndex] };
    showEditedSelection(selection);
    global.webkit?.messageHandlers?.abcNotationSelection?.postMessage(selection);
    await audio.play([{ ...note, pitches: [selection.midi] }], true);
  }

  function filename(title) {
    const clean = (title || "partitur").normalize("NFKD").replace(/[^\w.-]+/g, "-").replace(/^-+|-+$/g, "").toLowerCase();
    return `${clean || "partitur"}.mid`;
  }

  function exportMidi(tune) {
    const bytes = global.ABCJS.synth.getMidiFile(tune, { midiOutputType: "binary" });
    const name = filename(tune.metaText?.title);
    const nativeExport = global.webkit?.messageHandlers?.abcNotationMIDIExport;
    if (nativeExport) {
      nativeExport.postMessage({ filename: name, bytes: Array.from(bytes) });
      return;
    }
    const link = document.createElement("a");
    link.download = name;
    link.href = URL.createObjectURL(new Blob([bytes], { type: "audio/midi" }));
    link.click();
    setTimeout(() => URL.revokeObjectURL(link.href), 0);
  }

  function arrangement(source) {
    const tracks = [...source.matchAll(/^V:\s*([^\s]+)(?:.*?name="([^"]+)")?/gm)]
      .map(match => match[2] || match[1]);
    const sections = [...source.matchAll(/(?:^P:\s*|\[P:\s*)([^\]\n]+)/gm)]
      .map(match => match[1].trim());
    return { tracks: [...new Set(tracks)], sections: [...new Set(sections)] };
  }

  function addArrangement(block, source) {
    const plan = arrangement(source);
    if (plan.tracks.length < 2 && !plan.sections.length) return;
    const summary = document.createElement("div");
    summary.className = "cartograph-abc-arrangement";
    if (plan.tracks.length) summary.append(`Tracks: ${plan.tracks.join(" · ")}`);
    if (plan.sections.length) summary.append(`${plan.tracks.length ? " — " : ""}Abschnitte: ${plan.sections.join(" · ")}`);
    block.prepend(summary);
  }

  function hideContinuationInstrumentNames(block) {
    const names = Array.from(block.querySelectorAll(".abcjs-instrument-name"));
    names
      .filter(name => name.textContent.trim() === "Akkordе")
      .forEach(name => name.style.visibility = "hidden");
  }

  function sourceWithLayoutDefaults(source) {
    const defaults = [];
    if (!/^%%barsperstaff\b/m.test(source)) defaults.push("%%barsperstaff 4");
    if (!/^%%stretchlast\b/m.test(source)) defaults.push("%%stretchlast true");
    return defaults.length ? `${defaults.join("\n")}\n${source}` : source;
  }

  function compactNotationSource(source) {
    return source
      .replace(/^T:.*(?:\n|$)/gm, "")
      .replace(/"[^"\n]+"(?=\s*\[)/g, "");
  }

  function addCompactHeader(block, source, tune) {
    const symbol = source.match(/"([^"\n]+)"(?=\s*\[)/)?.[1]?.trim();
    const title = tune.metaText?.title?.trim();
    if (!symbol && !title) return;

    const header = document.createElement("div");
    header.className = "cartograph-abc-compact-header";
    const symbolElement = document.createElement("strong");
    symbolElement.className = "cartograph-abc-compact-symbol";
    symbolElement.textContent = symbol || title;
    header.append(symbolElement);
    if (symbol && title && title !== symbol) {
      const titleElement = document.createElement("span");
      titleElement.className = "cartograph-abc-compact-title";
      titleElement.textContent = title;
      header.append(titleElement);
    }
    block.append(header);
  }

  function addTrebleStaffGuides(block, tune) {
    const tuneStaffs = tune.lines.flatMap(line => line.staff || []);
    const renderedStaffs = Array.from(block.querySelectorAll(".abcjs-staff"));
    if (renderedStaffs.length !== tuneStaffs.length) {
      throw new Error(`Orientierungslinien konnten nicht zugeordnet werden (${renderedStaffs.length}/${tuneStaffs.length} Notensysteme).`);
    }

    renderedStaffs.forEach((staffElement, index) => {
      if (!String(tuneStaffs[index].clef?.type || "").startsWith("treble")) return;
      const box = staffElement.getBBox();
      if (![box.x, box.y, box.width, box.height].every(Number.isFinite) || box.width <= 0 || box.height <= 0) {
        throw new Error(`Orientierungslinie ${index + 1} hat ungültige Abmessungen.`);
      }
      const gap = box.height / 4;
      const svg = staffElement.ownerSVGElement;
      const group = document.createElementNS("http://www.w3.org/2000/svg", "g");
      group.classList.add("cartograph-abc-staff-guides");
      [
        { name: "middle", label: "H4", y: box.y + 2 * gap },
        { name: "g", label: "G4", y: box.y + 3 * gap }
      ].forEach(guide => {
        const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
        line.setAttribute("x1", box.x);
        line.setAttribute("x2", box.x + box.width);
        line.setAttribute("y1", guide.y);
        line.setAttribute("y2", guide.y);
        line.classList.add("cartograph-abc-guide", `cartograph-abc-guide--${guide.name}`);
        group.append(line);

        const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
        label.setAttribute("x", box.x + box.width - 2);
        label.setAttribute("y", guide.y - 2);
        label.textContent = guide.label;
        label.classList.add("cartograph-abc-guide-label", `cartograph-abc-guide-label--${guide.name}`);
        group.append(label);
      });
      svg.append(group);
    });
  }

  function render(block) {
    const source = block.dataset.source || "";
    block.replaceChildren();
    block.classList.remove("cartograph-abc--compact", "cartograph-abc--error");
    delete block.dataset.error;

    try {
      if (!global.ABCJS || typeof global.ABCJS.renderAbc !== "function") throw new Error("ABC-Renderer konnte nicht geladen werden.");
      if (!source.trim()) throw new Error("Die Partitur ist leer.");
      if (source.includes("__cartograph_error=")) throw new Error(source.split("__cartograph_error=", 2)[1].trim());

      let sequence;
      const renderOptions = {
        add_classes: true,
        responsive: "resize",
        clickListener: async (element, _tune, _classes, analysis) => {
          if (sequence?.elementNotes.get(element)) {
            try {
              await selectEditableNote(element, analysis);
            } catch (error) {
              const detail = `Ton konnte nicht abgespielt werden: ${message(error)}`;
              let output = block.querySelector(".cartograph-abc-audio-error");
              if (!output) {
                output = document.createElement("span");
                output.className = "cartograph-abc-audio-error";
                block.prepend(output);
              }
              output.textContent = detail;
              console.error("CartoGraph ABC audio error", error);
            }
          }
        }
      };
      const renderTunes = (options = renderOptions, notationSource = source) => {
        const rendered = global.ABCJS.renderAbc(block, sourceWithLayoutDefaults(notationSource), options);
        if (!rendered.length) throw new Error("ABC enthält keine darstellbare Partitur.");
        const warnings = rendered.flatMap(tune => tune.warnings || []).filter(Boolean);
        if (warnings.length) throw new Error(warnings.join("\n"));
        return rendered;
      };
      let tunes = renderTunes();
      const originalTune = tunes[0];
      sequence = playableSequence(tunes[0]);
      if (isSingleChordSequence(sequence)) {
        block.classList.add("cartograph-abc--compact");
        block.replaceChildren();
        tunes = renderTunes({ ...renderOptions, scale: 1.25, staffwidth: 150 }, compactNotationSource(source));
        sequence = playableSequence(tunes[0]);
        addCompactHeader(block, source, originalTune);
      }
      addTrebleStaffGuides(block, tunes[0]);
      hideContinuationInstrumentNames(block);
      scores.set(block, { sequence, tune: originalTune });
      if (!block.classList.contains("cartograph-abc--compact")) addArrangement(block, source);
      return { block };
    } catch (error) {
      const detail = message(error);
      block.classList.add("cartograph-abc--error");
      block.dataset.error = detail;
      const output = document.createElement("pre");
      output.textContent = "ABC-Partitur konnte nicht gerendert werden.\n" + detail;
      block.appendChild(output);
      console.error("CartoGraph ABC error", { source, detail });
      return { block, error: detail };
    }
  }

  function renderAll(root) {
    return Array.from((root || document).querySelectorAll("[data-cartograph-abc]")).map(render);
  }

  function score() {
    const block = document.querySelector("[data-cartograph-abc]");
    const value = block && scores.get(block);
    if (!value) throw new Error("Die Partitur ist noch nicht bereit.");
    return value;
  }

  document.addEventListener("keydown", event => {
    if (!editedSelection || (event.key !== "ArrowUp" && event.key !== "ArrowDown")) return;
    event.preventDefault();
    const delta = event.key === "ArrowUp" ? 1 : -1;
    global.webkit?.messageHandlers?.abcNotationTranspose?.postMessage({ selection: editedSelection, delta });
  });

  async function playAll() {
    const { sequence } = score();
    await audio.play(sequence.notes, true);
  }

  async function playMeasure(index) {
    const notes = score().sequence.measures[index];
    if (!notes?.length) throw new Error(`Takt ${index + 1} enthält keine abspielbaren Noten.`);
    await audio.play(notes, true);
  }

  async function loopMeasure(index) {
    const notes = score().sequence.measures[index];
    if (!notes?.length) throw new Error(`Takt ${index + 1} enthält keine abspielbaren Noten.`);
    await audio.loop(notes);
  }

  function setLiveMIDINotes(midiNotes) {
    document.querySelectorAll(".cartograph-abc-midi-live").forEach(element => {
      element.classList.remove("cartograph-abc-midi-live");
    });
    const pitchClasses = new Set((midiNotes || []).map(note => Number(note) % 12));
    if (!pitchClasses.size) return;
    score().sequence.notes.forEach(note => {
      if (!note.pitches.some(pitch => pitchClasses.has(pitch % 12))) return;
      note.elements.forEach(element => element.classList.add("cartograph-abc-midi-live"));
    });
  }

  function clearSelection() {
    document.querySelectorAll(".cartograph-abc-selected-measure,.cartograph-abc-selected-chord").forEach(element => {
      element.classList.remove("cartograph-abc-selected-measure", "cartograph-abc-selected-chord");
    });
  }

  function highlightChord(measure, pitches) {
    clearSelection();
    const selected = [...new Set((pitches || []).map(Number))].sort((a, b) => a - b);
    const sequence = score().sequence;
    const measuredNotes = sequence.measures[Number(measure)] || [];
    const matchingNotes = sequence.notes.filter(note => {
      const notePitches = [...new Set(note.pitches)].sort((a, b) => a - b);
      return notePitches.length === selected.length && notePitches.every((pitch, index) => pitch === selected[index]);
    });
    const notes = measuredNotes.length ? measuredNotes : matchingNotes;
    notes.forEach(note => note.elements.forEach(element => element.classList.add("cartograph-abc-selected-measure")));
    const measuredMatches = notes.filter(note => matchingNotes.includes(note));
    (measuredMatches.length ? measuredMatches : matchingNotes).forEach(note => {
      note.elements.forEach(element => element.classList.add("cartograph-abc-selected-chord"));
    });
    return notes.length > 0 || matchingNotes.length > 0;
  }


  function measureCount() {
    const measures = score().sequence.measures;
    let count = measures.length;
    while (count > 0 && !measures[count - 1]?.length) count -= 1;
    return count;
  }

  function isSingleChord() {
    return isSingleChordSequence(score().sequence);
  }

  function singleChord() {
    const sequence = score().sequence;
    return isSingleChordSequence(sequence) ? { pitches: sequence.notes.flatMap(note => note.pitches).sort((a, b) => a - b) } : null;
  }

  global.CartoGraphABC = {
    renderAll,
    playAll,
    playMeasure,
    loopMeasure,
    setLiveMIDINotes,
    highlightChord,
    clearSelection,
    showEditedSelection,
    showPitchSelection,
    setEditedSelectionColor,
    measureCount,
    isSingleChord,
    singleChord,
    exportMidi: () => exportMidi(score().tune),
    stopPlayback: () => audio.stop()
  };
  const ready = () => renderAll(document);
  global.cartoGraphABCReady = document.readyState === "loading"
    ? new Promise(resolve => document.addEventListener("DOMContentLoaded", () => resolve(ready()), { once: true }))
    : Promise.resolve(ready());
})(window);
