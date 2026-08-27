import { useEffect, useRef } from 'react';

interface ParticleButtonProps {
    onClick?: () => void;
    className?: string;
    particleColor?: string;
    isLoading?: boolean;
    inputValue?: string;
}

// Tokens que pintam as partículas. O canvas 2D não resolve `var(--x)` em
// `fillStyle`, então lemos os tokens do elemento uma vez.
const PALETA_TOKENS = ['--primary', '--foreground', '--brand-gold-deep', '--success'];

function lerPaleta(el: HTMLElement): string[] {
    const estilo = getComputedStyle(el);
    return PALETA_TOKENS.map((t) => `hsl(${estilo.getPropertyValue(t).trim()})`);
}

export function ParticleButton({ onClick, className = '', isLoading = false, inputValue = '' }: ParticleButtonProps) {
    const containerRef = useRef<HTMLDivElement>(null);
    const canvasRef = useRef<HTMLCanvasElement>(null);


    // Refs for animation loop access without re-triggering effect
    const particlesRef = useRef<any[]>([]);
    const hoverRef = useRef(false);
    const loadingRef = useRef(isLoading);
    const inputRef = useRef(inputValue);

    // Update refs when props change
    useEffect(() => {
        loadingRef.current = isLoading;
    }, [isLoading]);

    useEffect(() => {
        inputRef.current = inputValue;
    }, [inputValue]);

    // Handlers to update ref
    const handleMouseEnter = () => {
        hoverRef.current = true;
    };
    const handleMouseLeave = () => {
        hoverRef.current = false;
    };

    useEffect(() => {
        const container = containerRef.current;
        const canvas = canvasRef.current;
        if (!container || !canvas) return;

        const ctx = canvas.getContext('2d', { alpha: true });
        if (!ctx) return;

        // Initialize Particles ONCE
        if (particlesRef.current.length === 0) {
            const particleCount = 350;
            const brandColors = lerPaleta(canvas);
            const phi = Math.PI * (3 - Math.sqrt(5));

            const getTrianglePoint = (p1: { x: number, y: number }, p2: { x: number, y: number }, p3: { x: number, y: number }) => {
                const r1 = Math.random();
                const r2 = Math.random();
                const sqrtR1 = Math.sqrt(r1);
                const A = 1 - sqrtR1;
                const B = sqrtR1 * (1 - r2);
                const C = sqrtR1 * r2;
                return {
                    x: A * p1.x + B * p2.x + C * p3.x,
                    y: A * p1.y + B * p2.y + C * p3.y
                };
            };

            const tip = { x: 0.6, y: 0 };
            const top = { x: -0.5, y: 0.5 };
            const bottom = { x: -0.5, y: -0.5 };
            const notch = { x: -0.2, y: 0 };

            particlesRef.current = Array.from({ length: particleCount }).map((_, i) => {
                // Sphere Coords
                const y = 1 - (i / (particleCount - 1)) * 2;
                const radius = Math.sqrt(1 - y * y);
                const theta = phi * i;
                const sX = Math.cos(theta) * radius;
                const sY = y;
                const sZ = Math.sin(theta) * radius;

                // Triangle Coords
                const isTop = Math.random() > 0.5;
                const triP = isTop ? getTrianglePoint(tip, top, notch) : getTrianglePoint(tip, bottom, notch);
                const tX = triP.x;
                const tY = triP.y;
                const tZ = (Math.random() - 0.5) * 0.4;

                return {
                    sphereX: sX, sphereY: sY, sphereZ: sZ,
                    triX: tX, triY: tY, triZ: tZ,
                    x: sX, y: sY, z: sZ, // Initialize at sphere
                    phase: Math.random() * Math.PI * 2,
                    color: brandColors[i % brandColors.length],
                    size: 1.8 + Math.random() // Slightly bigger
                };
            });
        }

        const handleResize = () => {
            if (!container || !canvas) return;
            const width = container.clientWidth;
            const height = container.clientHeight;
            const dpr = Math.max(window.devicePixelRatio || 2, 2);
            canvas.width = width * dpr;
            canvas.height = height * dpr;
            canvas.style.width = width + 'px';
            canvas.style.height = height + 'px';
            ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
            ctx.imageSmoothingEnabled = true;
            ctx.globalCompositeOperation = 'lighter';
        };

        handleResize();
        const resizeObserver = new ResizeObserver(() => handleResize());
        resizeObserver.observe(container);

        let rotationY = 0;
        let rotationX = 0;
        let animationId: number;

        const animate = () => {
            const width = container.clientWidth;
            const height = container.clientHeight;

            ctx.clearRect(0, 0, width, height);

            const centerX = width / 2;
            const centerY = height / 2;

            // Read Refs
            const isHovered = hoverRef.current;
            const isLoading = loadingRef.current;
            const inputVal = inputRef.current;

            const targetMorph = isLoading ? 1 : Math.min(inputVal.length / 8, 1);

            let currentScale = (Math.min(width, height) / 2) * 0.85;
            const time = Date.now() / 1000;

            if (isLoading) {
                rotationY += 0.2;
                rotationX = Math.sin(time * 5) * 0.3;
                const pulse = 1 + Math.sin(time * 10) * 0.15;
                currentScale *= pulse;
            } else {
                const hoverFactor = isHovered ? 1 : 0;
                const rotSpeed = 0.01 + (hoverFactor * 0.08) + (targetMorph * 0.02);
                rotationY += rotSpeed;
                rotationX = (Math.sin(time * 0.5) * 0.3) * (1 - targetMorph) + (Math.sin(time * 2) * 0.1 * targetMorph);
            }

            particlesRef.current.forEach(p => {
                const targetX = p.sphereX * (1 - targetMorph) + p.triX * targetMorph;
                const targetY = p.sphereY * (1 - targetMorph) + p.triY * targetMorph;
                const targetZ = p.sphereZ * (1 - targetMorph) + p.triZ * targetMorph;

                // Soft seek logic can go here if we wanted smooth transition over time,
                // but direct interpolation based on morph factor (which changes per keystroke) is snappy enough.
                let x = targetX;
                let y = targetY;
                let z = targetZ;

                if (isLoading) {
                    const jitter = Math.sin(time * 25 + p.phase) * 0.15;
                    x += jitter; y += jitter; z += jitter;
                } else {
                    const sphereWobble = Math.sin(time * 2 + p.phase) * 0.05;
                    const triWobble = Math.sin(time * 8 + p.phase) * 0.03;
                    const wobble = sphereWobble * (1 - targetMorph) + triWobble * targetMorph;
                    const hoverExp = isHovered ? (Math.sin(time * 15 + p.phase) * 0.1) : 0;
                    x += wobble + hoverExp;
                    y += wobble + hoverExp;
                    z += wobble + hoverExp;
                }

                let x2 = x * Math.cos(rotationY) - z * Math.sin(rotationY);
                let z2 = x * Math.sin(rotationY) + z * Math.cos(rotationY);
                x = x2; z = z2;

                let y2 = y * Math.cos(rotationX) - z * Math.sin(rotationX);
                let z3 = y * Math.sin(rotationX) + z * Math.cos(rotationX);
                y = y2; z = z3;

                x *= currentScale;
                y *= currentScale;
                z *= currentScale;

                const fov = 250;
                const scale = fov / (fov + z + 100);
                const px = centerX + x * scale;
                const py = centerY + y * scale;

                const baseAlpha = 0.5 + (0.3 * targetMorph);
                const alpha = isLoading ? 0.9 : Math.max(baseAlpha, scale * scale);

                ctx.globalAlpha = alpha;
                ctx.fillStyle = p.color;

                ctx.beginPath();
                const drawSize = p.size * scale * (1 + targetMorph * 0.5);
                ctx.arc(px, py, drawSize, 0, Math.PI * 2);
                ctx.fill();
            });

            animationId = requestAnimationFrame(animate);
        };

        animate();

        return () => {
            cancelAnimationFrame(animationId);
            resizeObserver.disconnect();
        };
    }, []); // Only run once on mount!

    return (
        <div
            ref={containerRef}
            className={`relative flex items-center justify-center overflow-hidden rounded-full transition-all duration-300 ${className}`}
            style={{
                cursor: isLoading ? 'wait' : (inputValue.length > 0 ? 'pointer' : 'default'),
                opacity: (inputValue.length > 0 || isLoading) ? 1 : 0.7
            }}
            onClick={(isLoading || inputValue.length === 0) ? undefined : onClick}
            onMouseEnter={handleMouseEnter}
            onMouseLeave={handleMouseLeave}
        >
            <canvas
                ref={canvasRef}
                className="absolute inset-0 pointer-events-none w-full h-full"
            />
        </div>
    );
}
