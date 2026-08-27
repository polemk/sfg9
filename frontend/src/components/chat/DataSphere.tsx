import { useEffect, useRef, useState } from 'react';

interface DataSphereProps {
    onClick?: () => void;
    className?: string;
    particleColor?: string;
    theme?: 'light' | 'dark' | 'system';
}

// Tokens que pintam a esfera. O canvas 2D não resolve `var(--x)` em `fillStyle`,
// então lemos os tokens do elemento uma vez e guardamos a cor já resolvida.
const PALETA_TOKENS = ['--primary', '--foreground', '--brand-gold-deep', '--muted-foreground'];

function lerPaleta(el: HTMLElement): string[] {
    const estilo = getComputedStyle(el);
    return PALETA_TOKENS.map((t) => `hsl(${estilo.getPropertyValue(t).trim()})`);
}

export function DataSphere({ onClick, className = '', particleColor = 'hsl(var(--primary))', theme = 'dark' }: DataSphereProps) {
    const containerRef = useRef<HTMLDivElement>(null);
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const [isHovered, setIsHovered] = useState(false);

    useEffect(() => {
        const container = containerRef.current;
        const canvas = canvasRef.current;
        if (!container || !canvas) return;

        const ctx = canvas.getContext('2d', { alpha: true });
        if (!ctx) return;

        // Config
        const particleCount = 400; // Increased for density

        // State
        let width = 0;
        let height = 0;
        let rotationX = 0;
        let rotationY = 0;
        let animationId: number;

        // Paleta da marca — vem dos tokens, então já acompanha claro/escuro
        // sozinha (não há mais uma lista de hex por modo).
        const brandColors = lerPaleta(canvas);

        // Particles (Golden Spiral)
        const phi = Math.PI * (3 - Math.sqrt(5));
        const particles = Array.from({ length: particleCount }).map((_, i) => {
            const y = 1 - (i / (particleCount - 1)) * 2;
            const radius = Math.sqrt(1 - y * y);
            const theta = phi * i;
            return {
                baseX: Math.cos(theta) * radius,
                baseY: y,
                baseZ: Math.sin(theta) * radius,
                phase: Math.random() * Math.PI * 2,
                color: brandColors[i % brandColors.length] // Cycle through colors
            };
        });

        const handleResize = () => {
            if (!container || !canvas) return;

            width = container.clientWidth;
            height = container.clientHeight;

            // Cap DPR at 3 for performance, while keeping it crisp.
            // Dynamic High DPI handling
            // User wants to zoom in significantly.
            // Since we removed expensive effects (shadows), we can afford ultra-high res.
            const dpr = Math.max(window.devicePixelRatio || 2, 6);

            canvas.width = width * dpr;
            canvas.height = height * dpr;

            canvas.style.width = `${width}px`;
            canvas.style.height = `${height}px`;

            ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

            // Ensure smooth scaling
            ctx.imageSmoothingEnabled = true;
            ctx.imageSmoothingQuality = 'high';

            // 'lighter' gives that nice additive neon glow when particles overlap
            // It's much cheaper than shadowBlur
            ctx.globalCompositeOperation = 'lighter';
        };

        handleResize();

        const resizeObserver = new ResizeObserver(() => handleResize());
        resizeObserver.observe(container);
        window.addEventListener('resize', handleResize);

        let currentHoverFactor = 0; // 0 to 1

        const animate = () => {
            // Clear
            ctx.clearRect(0, 0, width, height);

            const centerX = width / 2;
            const centerY = height / 2;

            // Allow almost full width (width/2 * 1.0 would touch edges). 
            // Using 0.95 to keep particles safe from clipping at edges + wobbling.
            const sphereRadiusX = (width / 2) * 0.95;
            const sphereRadiusY = (height / 2) * 0.95;

            // Lerp hover factor
            const targetHover = isHovered ? 1 : 0;
            // Smooth easing (0.05 is the interpolation speed)
            currentHoverFactor += (targetHover - currentHoverFactor) * 0.05;

            // Rotation logic interpolated
            const baseSpeed = 0.005;
            const maxSpeed = 0.02;
            const currentSpeed = baseSpeed + (maxSpeed - baseSpeed) * currentHoverFactor;

            rotationY += currentSpeed;
            rotationX += currentSpeed * 0.5;

            particles.forEach(p => {
                // 1. Rotation (Logic applies to a unit sphere first)
                let x = p.baseX;
                let y = p.baseY;
                let z = p.baseZ;

                // Rotate Y
                let x2 = x * Math.cos(rotationY) - z * Math.sin(rotationY);
                let z2 = x * Math.sin(rotationY) + z * Math.cos(rotationY);
                x = x2; z = z2;

                // Rotate X
                let y2 = y * Math.cos(rotationX) - z * Math.sin(rotationX);
                let z3 = y * Math.sin(rotationX) + z * Math.cos(rotationX);
                y = y2; z = z3;

                // Apply separate radii for deformation
                x *= sphereRadiusX;
                y *= sphereRadiusY;
                z *= sphereRadiusX; // Keep depth relative to width

                // 2. Swarm effect interpolated
                // Only compute sin/cos if factor > 0.001 to save math? 
                // Actually JS math is fast enough. 
                // We modulate magnitude by currentHoverFactor.
                if (currentHoverFactor > 0.001) {
                    const time = Date.now() / 1000;
                    const wobbleBase = Math.sin(time * 3 + p.phase);
                    // Max wobble is 15% of radius.
                    const wobble = wobbleBase * (sphereRadiusX * 0.15 * currentHoverFactor);

                    x += wobble * (x / sphereRadiusX);
                    y += wobble * (y / sphereRadiusY);
                    z += wobble * (z / sphereRadiusX);
                }

                // 3. Perspective
                const fov = 300;
                const scale = fov / (fov + z + 250);

                const px = centerX + x * scale;
                const py = centerY + y * scale;

                // Draw
                // Increased base alpha for brightness
                const alpha = Math.max(0.3, scale * scale * 0.9);

                ctx.globalAlpha = alpha;
                ctx.fillStyle = p.color;

                ctx.beginPath();
                ctx.arc(px, py, 1.5 * scale, 0, Math.PI * 2);
                ctx.fill();
            });

            animationId = requestAnimationFrame(animate);
        };

        animate();

        return () => {
            cancelAnimationFrame(animationId);
            resizeObserver.disconnect();
            window.removeEventListener('resize', handleResize);
        };
    }, [isHovered, particleColor, theme]);

    // Precise hover detection using ellipsoid math
    const handleMouseMove = (e: React.MouseEvent<HTMLDivElement>) => {
        if (!containerRef.current) return;
        const rect = containerRef.current.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;

        const width = rect.width;
        const height = rect.height;
        const centerX = width / 2;
        const centerY = height / 2;

        // Define the visual ellipsoid (0.95 factor matches the rendering)
        const radiusX = (width / 2) * 0.95;
        const radiusY = (height / 2) * 0.95;

        const dx = x - centerX;
        const dy = y - centerY;

        // Check if inside ellipsoid: (dx/rx)^2 + (dy/ry)^2 <= 1
        // We add a small buffer (1.1) to make it easy to grab, but not square-boxed
        const normalizedDist = (dx * dx) / (radiusX * radiusX) + (dy * dy) / (radiusY * radiusY);

        if (normalizedDist <= 1.0) {
            setIsHovered(true);
        } else {
            setIsHovered(false);
        }
    };

    return (
        <div
            ref={containerRef}
            // Removed generic CSS drop-shadow to avoid blurred rasterization
            // Added specific glow when hovered via CSS for container boundary if needed, but canvas handles internal glow
            className={`relative transition-all duration-500 ease-out ${isHovered ? 'scale-110' : ''} ${className}`}
            onClick={onClick}
            onMouseMove={handleMouseMove}
            onMouseEnter={() => setIsHovered(true)}
            onMouseLeave={() => setIsHovered(false)}
            role="button"
            tabIndex={0}
            aria-label="Chat AI"
        >
            <canvas
                ref={canvasRef}
                className="block pointer-events-none w-full h-full"
            />
        </div>
    );
}

