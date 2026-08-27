import { useEffect, useRef } from 'react';
import { Button } from '@/components/ui/Button';

interface RewardOverlayProps {
    onClose: () => void;
    onRedeem: () => void;
}

// Tokens usados pelo confete. O canvas 2D não resolve `var(--x)` em `fillStyle`,
// então lemos os tokens do próprio elemento uma vez e passamos a cor já pronta.
const CONFETTI_TOKENS = ['--primary', '--success', '--info', '--warning', '--foreground'];

function lerTokens(el: HTMLElement): string[] {
    const estilo = getComputedStyle(el);
    return CONFETTI_TOKENS.map((t) => `hsl(${estilo.getPropertyValue(t).trim()})`);
}

export function RewardOverlay({ onClose, onRedeem }: RewardOverlayProps) {
    const canvasRef = useRef<HTMLCanvasElement>(null);

    useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas) return;

        const ctx = canvas.getContext('2d');
        if (!ctx) return;

        let width = canvas.width = canvas.parentElement?.clientWidth || 300;
        let height = canvas.height = canvas.parentElement?.clientHeight || 600;

        const particles: any[] = [];
        const colors = lerTokens(canvas);

        // Create Explosion
        for (let i = 0; i < 400; i++) {
            const speed = Math.random() * 8 + 2;
            const angle = Math.random() * Math.PI * 2;
            particles.push({
                x: width / 2,
                y: height / 2,
                vx: Math.cos(angle) * speed,
                vy: Math.sin(angle) * speed,
                color: colors[Math.floor(Math.random() * colors.length)],
                alpha: 1,
                size: Math.random() * 3 + 1,
                decay: Math.random() * 0.01 + 0.005
            });
        }

        let animationId: number;
        const animate = () => {
            ctx.clearRect(0, 0, width, height);

            // We want trails? No, clear rect for crisp movement, maybe faint trails
            // Let's stick to clearRect for performance and clarity with the overlay content

            ctx.globalCompositeOperation = 'lighter';

            particles.forEach((p, index) => {
                p.x += p.vx;
                p.y += p.vy;
                p.vy += 0.05; // Gravity
                p.vx *= 0.98; // Friction
                p.vy *= 0.98;
                p.alpha -= p.decay;

                if (p.alpha <= 0) {
                    particles.splice(index, 1);
                    return;
                }

                ctx.globalAlpha = p.alpha;
                ctx.fillStyle = p.color;
                ctx.beginPath();
                ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
                ctx.fill();
            });

            if (particles.length > 0) {
                animationId = requestAnimationFrame(animate);
            }
        };

        animate();

        return () => cancelAnimationFrame(animationId);
    }, []);

    return (
        <div className="surface-dark absolute inset-0 z-modal-backdrop flex flex-col items-center justify-center bg-brand-ink/80 backdrop-blur-sm text-center p-6 animate-in fade-in duration-300 pointer-events-auto">
            <canvas ref={canvasRef} className="absolute inset-0 pointer-events-none" />

            <div className="relative z-modal space-y-6">
                <div className="space-y-2">
                    <h2 className="text-4xl font-title font-bold tracking-tight text-primary animate-bounce">
                        e aí meu cria!
                    </h2>
                    <p className="text-muted-foreground">
                        Você encontrou um cupom secreto por ser curioso!
                    </p>
                </div>

                <div className="bg-card p-4 rounded-lg border border-border backdrop-blur-md shadow-e2">
                    <p className="text-sm text-muted-foreground uppercase tracking-wider mb-1">Seu Cupom</p>
                    <code className="text-2xl font-numeric font-bold text-foreground selection:bg-primary selection:text-primary-foreground">
                        CAMPFIRE20
                    </code>
                </div>

                <div className="space-y-3 w-full">
                    <Button
                        variant="primary"
                        onClick={onRedeem}
                        className="w-full h-12 text-lg"
                    >
                        Resgatar Agora
                    </Button>

                    <Button
                        variant="link"
                        size="sm"
                        onClick={onClose}
                        className="w-full"
                    >
                        Talvez mais tarde
                    </Button>
                </div>
            </div>
        </div>
    );
}
