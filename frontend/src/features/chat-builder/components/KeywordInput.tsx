
import React, { useState, KeyboardEvent } from 'react';
import { X, Sparkles } from 'lucide-react';

interface KeywordInputProps {
    value: string[];
    onChange: (value: string[]) => void;
    placeholder?: string;
}

export function KeywordInput({ value, onChange, placeholder }: KeywordInputProps) {
    const [inputValue, setInputValue] = useState('');

    const addKeyword = (text: string) => {
        const trimmed = text.trim();
        if (trimmed && !value.includes(trimmed)) {
            onChange([...value, trimmed]);
        }
        setInputValue('');
    };

    const removeKeyword = (keyword: string) => {
        onChange(value.filter((k) => k !== keyword));
    };

    const handleKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
        if (e.key === 'Enter' || e.key === ',') {
            e.preventDefault();
            addKeyword(inputValue);
        } else if (e.key === 'Backspace' && !inputValue && value.length > 0) {
            removeKeyword(value[value.length - 1]);
        }
    };

    return (
        <div className="space-y-2">
            <div className="flex flex-wrap gap-1.5 p-2 bg-muted/30 border border-input rounded-lg focus-within:ring-2 focus-within:ring-ring focus-within:border-primary transition-all min-h-10">
                {/* Balão de palavra-chave: gatilho do fluxo, por isso ouro (primary). */}
                {value.map((keyword) => (
                    <button
                        key={keyword}
                        type="button"
                        onClick={() => removeKeyword(keyword)}
                        className="flex items-center gap-1.5 px-2.5 py-1 bg-primary/10 border border-primary/20 text-primary rounded-full text-xs font-medium cursor-pointer hover:bg-primary/20 transition-colors group focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                        <Sparkles className="w-3 h-3 text-primary/70" />
                        {keyword}
                        <X className="w-3 h-3 text-primary/70 opacity-0 group-hover:opacity-100 transition-opacity" />
                    </button>
                ))}
                <input
                    type="text"
                    value={inputValue}
                    onChange={(e) => setInputValue(e.target.value)}
                    onKeyDown={handleKeyDown}
                    onBlur={() => addKeyword(inputValue)}
                    className="flex-grow bg-transparent border-none outline-none text-sm px-1 min-w-[120px]"
                    placeholder={value.length === 0 ? placeholder : ''}
                />
            </div>
            <p className="text-xs text-muted-foreground">
                Pressione <kbd className="font-sans px-1 bg-muted border border-border rounded-sm">Enter</kbd> ou <kbd className="font-sans px-1 bg-muted border border-border rounded-sm">,</kbd> para adicionar. Clique no balão para remover.
            </p>
        </div>
    );
}
