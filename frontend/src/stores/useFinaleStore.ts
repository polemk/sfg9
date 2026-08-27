import { create } from 'zustand';

interface FinaleStore {
    isFinale: boolean;
    invertProgress: number;
    isChatOpen: boolean;
    setIsFinale: (value: boolean) => void;
    setInvertProgress: (value: number) => void;
    openChat: () => void;
    closeChat: () => void;
}

export const useFinaleStore = create<FinaleStore>((set) => ({
    isFinale: false,
    invertProgress: 0,
    isChatOpen: false,
    setIsFinale: (value) => set({ isFinale: value }),
    setInvertProgress: (value) => set({ invertProgress: value }),
    openChat: () => set({ isChatOpen: true }),
    closeChat: () => set({ isChatOpen: false }),
}));
