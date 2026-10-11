// Mac と同じ Samantha の声を使う。無ければアメリカ英語、その次に英語の声
export function pickVoice(voices: SpeechSynthesisVoice[]): SpeechSynthesisVoice | undefined {
  const english = voices.filter((voice) => voice.lang.replace("_", "-").startsWith("en"));
  const us = english.filter((voice) => voice.lang.replace("_", "-") === "en-US");
  const samantha = us.filter((voice) => voice.name.startsWith("Samantha"));
  const enhanced = (list: SpeechSynthesisVoice[]) => list.find((voice) => /enhanced|premium/i.test(voice.name)) ?? list[0];
  return enhanced(samantha) ?? enhanced(us) ?? english[0];
}

export function say(text: string): Promise<void> {
  return new Promise((resolve) => {
    const utterance = new SpeechSynthesisUtterance(text);
    const voice = pickVoice(speechSynthesis.getVoices());
    utterance.lang = voice?.lang ?? "en-US";
    if (voice) utterance.voice = voice;
    utterance.onend = () => resolve();
    utterance.onerror = () => resolve();
    speechSynthesis.speak(utterance);
  });
}

export const canSpeak = () => typeof window !== "undefined" && "speechSynthesis" in window;
