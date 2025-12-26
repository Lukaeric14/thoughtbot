import fs from 'fs';
import { openai } from './openaiClient.js';

export async function transcribeAudio(audioFilePath: string): Promise<string> {
  const audioFile = fs.createReadStream(audioFilePath);

  const transcription = await openai.audio.transcriptions.create({
    file: audioFile,
    model: 'whisper-1',
    language: 'en',
  });

  return transcription.text;
}
