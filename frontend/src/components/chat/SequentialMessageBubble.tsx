import React, { useState, useEffect } from 'react';

// Simplified interface matching AIChatWidget expectations
interface Block {
    type: string;
    content?: string;
    seconds?: number;
    [key: string]: any;
}

interface ChatMessage {
    id: string;
    blocks?: Block[];
    content: string;
}

interface SequentialMessageBubbleProps {
    message: ChatMessage;
    onComplete?: () => void;
    // Fallback renderer for individual content blocks
    renderBlock: (block: Block, index: number) => React.ReactNode;
    isTyping?: boolean;
}

export function SequentialMessageBubble({ message, onComplete, renderBlock, isTyping }: SequentialMessageBubbleProps) {
    const blocks = message.blocks || [];
    // visibleIndex represents the block we are currently "processing" or have just finished processing.
    // Blocks from 0 to visibleIndex (exclusive) are definitely fully visible.
    // We determine render range based on the type of the current block.
    const [visibleIndex, setVisibleIndex] = useState(0);

    useEffect(() => {
        // If we've reached the end, call onComplete
        if (visibleIndex >= blocks.length) {
            if (onComplete) onComplete();
            return;
        }

        const currentBlock = blocks[visibleIndex];

        if (currentBlock.type === 'delay') {
            const delayMs = (currentBlock.seconds || 0) * 1000;
            const timer = setTimeout(() => {
                setVisibleIndex((prev) => prev + 1);
            }, delayMs);
            return () => clearTimeout(timer);
        } else {
            // It's content (text/image). Show it immediately and move to next.
            // We use a tiny timeout to ensure react render cycle updates, 
            // and to give a very subtle "sequential" feel even for consecutive texts.
            const timer = setTimeout(() => {
                setVisibleIndex((prev) => prev + 1);
            }, 50);
            return () => clearTimeout(timer);
        }
    }, [visibleIndex, blocks, onComplete]);

    // Render logic:
    // We want to render all blocks UP TO visibleIndex.
    // PLUS, if the blocks[visibleIndex] is NOT a delay (i.e. it's text), we want to render it NOW 
    // so the user sees it while the "50ms" timer ticks to move past it.
    // If blocks[visibleIndex] IS a delay, we do NOT render it (it's invisible waiting time).

    const currentIsDelay = blocks[visibleIndex]?.type === 'delay';
    const renderLimit = currentIsDelay ? visibleIndex : visibleIndex + 1;
    const blocksToRender = blocks.slice(0, renderLimit);

    return (
        <div className="flex flex-col gap-1 w-full">
            {blocksToRender.map((block, idx) => {
                if (block.type === 'delay') return null;
                return (
                    <div key={idx} className="animate-in fade-in slide-in-from-bottom-1 duration-300">
                        {renderBlock(block, idx)}
                    </div>
                );
            })}

            {/* 
        Optional: Show visual typing indicator IF we are currently waiting on a delay?
        The user might want to see "..." while waiting 5 seconds.
        If visibleIndex points to a delay, show loader.
      */}
            {blocks[visibleIndex]?.type === 'delay' && isTyping && (
                <div className="opacity-50 text-xs italic ml-1 mb-1 animate-pulse">...</div>
            )}
        </div>
    );
}
