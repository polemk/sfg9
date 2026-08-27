import { create } from 'zustand'

interface AudioPlayerState {
    isActive: boolean;
    youtubeUrl: string | null;
    songName: string | null;
    isPlaying: boolean;
    analyser: AnalyserNode | null;

    activatePlayer: (url: string, name: string) => void;
    deactivatePlayer: () => void;
    setPlaying: (playing: boolean) => void;
    setAnalyser: (analyser: AnalyserNode | null) => void;
}

export const useAudioPlayerStore = create<AudioPlayerState>((set) => ({
    isActive: false,
    youtubeUrl: null,
    songName: null,
    isPlaying: false,
    analyser: null,

    activatePlayer: (url, name) => set({ isActive: true, youtubeUrl: url, songName: name, isPlaying: true }),
    deactivatePlayer: () => set({ isActive: false, youtubeUrl: null, songName: null, isPlaying: false, analyser: null }),
    setPlaying: (playing) => set({ isPlaying: playing }),
    setAnalyser: (analyser) => set({ analyser }),
}))
