import { useState, useEffect } from 'react';

interface ParticleLoaderProps {
    className?: string;
}

export function ParticleLoader({ className = '' }: ParticleLoaderProps) {
    // Standard 3-dot bouncing animation ("Facebook style")
    return (
        <div className={`flex items-center justify-center gap-1.5 ${className}`}>
            <div className="w-2.5 h-2.5 bg-current rounded-full animate-bounce [animation-delay:-0.3s]"></div>
            <div className="w-2.5 h-2.5 bg-current rounded-full animate-bounce [animation-delay:-0.15s]"></div>
            <div className="w-2.5 h-2.5 bg-current rounded-full animate-bounce"></div>
        </div>
    );
}
