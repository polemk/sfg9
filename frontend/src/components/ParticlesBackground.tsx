import { useEffect, useState, useMemo, useRef } from "react";
import Particles, { initParticlesEngine } from "@tsparticles/react";
import { type Container, type ISourceOptions } from "@tsparticles/engine";
import { loadFull } from "tsparticles";

import { useTheme } from "@/hooks/useTheme";
import { useAudioPlayerStore } from "@/store/audioPlayerStore";

/**
 * Resolve um token de cor do tema para string concreta.
 *
 * O tsparticles faz o próprio parse de cor e não entende `var(--x)`, então o
 * valor precisa chegar já resolvido. A leitura é feita numa sonda com a classe
 * do tema aplicada — e não em `document.documentElement` — porque o `useTheme`
 * só grava a classe na raiz dentro de um efeito, ou seja, depois desta render.
 */
function corDoTema(tema: 'light' | 'dark', token: string): string {
  if (typeof document === 'undefined') return "transparent";
  const sonda = document.createElement("div");
  sonda.className = tema;
  sonda.style.display = "none";
  document.body.appendChild(sonda);
  const hsl = getComputedStyle(sonda).getPropertyValue(token).trim();
  sonda.remove();
  return hsl ? `hsl(${hsl})` : "transparent";
}

export const ParticlesBackground = () => {
  const { theme, setTheme } = useTheme();
  const [init, setInit] = useState(false);
  const previousThemeRef = useRef<'light' | 'dark' | null>(null);

  // this should be run only once per application lifetime
  useEffect(() => {
    initParticlesEngine(async (engine) => {
      // you can initiate the tsParticles instance (engine) here, adding custom shapes or presets
      // this loads the tsparticles package bundle, it's the easiest method for getting everything ready
      // starting from v2 you can add only the features you need reducing the bundle size
      await loadFull(engine);
    }).then(() => {
      setInit(true);
    });
  }, []);

  // Get audio state (used for theme switching and visualizer)
  const { analyser, isPlaying } = useAudioPlayerStore();

  // Force dark mode when music is playing (stars need dark background)
  useEffect(() => {
    if (isPlaying) {
      // Save current theme and switch to dark
      if (theme !== 'dark') {
        previousThemeRef.current = theme;
        setTheme('dark');
      }
    } else {
      // Restore previous theme when music stops
      if (previousThemeRef.current && previousThemeRef.current !== 'dark') {
        setTheme(previousThemeRef.current);
        previousThemeRef.current = null;
      }
    }
  }, [isPlaying, theme, setTheme]);

  // O tsparticles precisa da cor já resolvida — ver `corDoTema`.
  const cor = (token: string) => corDoTema(theme, token);

  const options: ISourceOptions = useMemo(
    () => ({
      autoPlay: true,
      background: {
        color: {
          value: "transparent",
        },
        image: "",
        position: "50% 50%",
        repeat: "no-repeat",
        size: "20%",
        opacity: 1,
      },
      backgroundMask: {
        composite: "destination-out",
        cover: {
          opacity: 1,
          color: {
            value: "",
          },
        },
        enable: false,
      },
      clear: true,
      defaultThemes: {},
      delay: 0,
      fullScreen: {
        enable: true,
        zIndex: 0,
      },
      detectRetina: false, // Performance: Disable retina rendering on mobile (prevents 3x calculation)
      duration: 0,
      fpsLimit: 60, // Performance: Cap at 60fps to save battery/thermal
      interactivity: {
        detectsOn: "window",
        events: {
          onClick: {
            enable: true,
            mode: "repulse",
          },
          onDiv: {
            selectors: [],
            enable: false,
            mode: [],
          },
          onHover: {
            enable: true,
            mode: "bubble",
          },
          parallax: {
            enable: false,
            force: 2,
            smooth: 10,
          },
          resize: {
            delay: 0.5,
            enable: true,
          },
        },
        modes: {
          trail: {
            delay: 1,
            pauseOnStop: false,
            quantity: 1,
          },
          attract: {
            distance: 200,
            duration: 0.4,
            easing: "ease-out-quad",
            factor: 1,
            maxSpeed: 50,
            speed: 1,
          },
          bounce: {
            distance: 200,
          },
          bubble: {
            distance: 250,
            duration: 2,
            mix: false,
            opacity: 0,
            size: 0,
          },
          divs: {
            distance: 200,
            duration: 0.4,
            mix: false,
            selectors: [],
          },
          connect: {
            distance: 80,
            links: {
              opacity: 0.5,
              radius: 60,
            },
          },
          grab: {
            distance: 400,
            links: {
              blink: false,
              consent: false,
              opacity: 1,
            },
          },
          push: {
            default: true,
            groups: [],
            quantity: 4,
          },
          remove: {
            quantity: 2,
          },
          repulse: {
            distance: 400,
            duration: 0.4,
            factor: 100,
            speed: 1,
            maxSpeed: 50,
            easing: "ease-out-quad",
            divs: {
              distance: 200,
              duration: 0.4,
              factor: 100,
              speed: 1,
              maxSpeed: 50,
              easing: "ease-out-quad",
              selectors: [],
            },
          },
          slow: {
            factor: 3,
            radius: 200,
          },
          particle: {
            replaceCursor: false,
            pauseOnStop: false,
            stopDelay: 0,
          },
          light: {
            area: {},
            gradient: {
              start: {
                value: cor("--background"),
              },
              stop: {
                value: cor("--brand-ink"),
              },
            },
            radius: 1000,
            shadow: {
              color: {
                value: cor("--brand-ink"),
              },
              length: 2000,
            },
          },
        },
      },
      manualParticles: [],
      particles: {
        bounce: {
          horizontal: {
            value: 1,
          },
          vertical: {
            value: 1,
          },
        },
        collisions: {
          absorb: {
            speed: 2,
          },
          bounce: {
            horizontal: {
              value: 1,
            },
            vertical: {
              value: 1,
            },
          },
          enable: false,
          maxSpeed: 50,
          mode: "bounce",
          overlap: {
            enable: true,
            retries: 0,
          },
        },
        color: {
          // No claro o ponto precisa de um cinza médio p/ aparecer sobre o
          // fundo morno; no escuro ele é o próprio texto.
          value: cor(theme === 'light' ? "--muted-foreground" : "--foreground"),
          animation: {
            h: {
              count: 0,
              enable: false,
              speed: 1,
              decay: 0,
              delay: 0,
              sync: true,
              offset: 0,
            },
            s: {
              count: 0,
              enable: false,
              speed: 1,
              decay: 0,
              delay: 0,
              sync: true,
              offset: 0,
            },
            l: {
              count: 0,
              enable: false,
              speed: 1,
              decay: 0,
              delay: 0,
              sync: true,
              offset: 0,
            },
          },
        },
        effect: {
          close: true,
          fill: true,
          options: {},
          type: [],
        },
        groups: {},
        move: {
          angle: {
            offset: 0,
            value: 90,
          },
          attract: {
            distance: 200,
            enable: false,
          },
          rotate: {
            x: 3000,
            y: 3000,
          },
          center: {
            x: 50,
            y: 50,
            mode: "percent",
            radius: 0,
          },
          decay: 0,
          distance: {},
          direction: "none",
          drift: 0,
          enable: true,
          gravity: {
            acceleration: 9.81,
            enable: false,
            inverse: false,
            maxSpeed: 50,
          },
          path: {
            clamp: true,
            delay: {
              value: 0,
            },
            enable: false,
            options: {},
          },
          outModes: {
            default: "out",
            bottom: "out",
            left: "out",
            right: "out",
            top: "out",
          },
          random: false,
          size: false,
          speed: {
            min: 0.1,
            max: 1,
          },
          spin: {
            acceleration: 0,
            enable: false,
          },
          straight: false,
          trail: {
            enable: false,
            length: 10,
            fill: {},
          },
          vibrate: false,
          warp: false,
        },
        number: {
          density: {
            enable: true,
            width: 1920,
            height: 1080,
          },
          limit: {
            mode: "delete",
            value: 0,
          },
          value: 80, // Performance: reduced from 160 for mobile safety
        },
        opacity: {
          value: {
            min: 0.15,
            max: 0.6,
          },
          animation: {
            count: 0,
            enable: true,
            speed: 1,
            decay: 0,
            delay: 0,
            sync: false,
            mode: "auto",
            startValue: "random",
            destroy: "none",
          },
        },
        reduceDuplicates: false,
        shadow: {
          blur: 0,
          color: {
            value: cor("--brand-ink"),
          },
          enable: false,
          offset: {
            x: 0,
            y: 0,
          },
        },
        shape: {
          close: true,
          fill: true,
          options: {},
          type: "circle",
        },
        size: {
          value: {
            min: 0.5,
            max: 1.8,
          },
          animation: {
            count: 0,
            enable: false,
            speed: 5,
            decay: 0,
            delay: 0,
            sync: false,
            mode: "auto",
            startValue: "random",
            destroy: "none",
          },
        },
        stroke: {
          width: 0,
        },
        zIndex: {
          value: 0,
          opacityRate: 1,
          sizeRate: 1,
          velocityRate: 1,
        },
        destroy: {
          bounds: {},
          mode: "none",
          split: {
            count: 1,
            factor: {
              value: 3,
            },
            rate: {
              value: {
                min: 4,
                max: 9,
              },
            },
            sizeOffset: true,
          },
        },
        roll: {
          darken: {
            enable: false,
            value: 0,
          },
          enable: false,
          enlighten: {
            enable: false,
            value: 0,
          },
          mode: "vertical",
          speed: 25,
        },
        tilt: {
          value: 0,
          animation: {
            enable: false,
            speed: 0,
            decay: 0,
            sync: false,
          },
          direction: "clockwise",
          enable: false,
        },
        twinkle: {
          lines: {
            enable: false,
            frequency: 0.05,
            opacity: 1,
          },
          particles: {
            enable: false,
            frequency: 0.05,
            opacity: 1,
          },
        },
        wobble: {
          distance: 5,
          enable: false,
          speed: {
            angle: 50,
            move: 10,
          },
        },
        life: {
          count: 0,
          delay: {
            value: 0,
            sync: false,
          },
          duration: {
            value: 0,
            sync: false,
          },
        },
        rotate: {
          value: 0,
          animation: {
            enable: false,
            speed: 0,
            decay: 0,
            sync: false,
          },
          direction: "clockwise",
          path: false,
        },
        orbit: {
          animation: {
            count: 0,
            enable: false,
            speed: 1,
            decay: 0,
            delay: 0,
            sync: false,
          },
          enable: false,
          opacity: 1,
          rotation: {
            value: 45,
          },
          width: 1,
        },
        links: {
          blink: false,
          color: {
            value: cor("--foreground"),
          },
          consent: false,
          distance: 150,
          enable: false,
          frequency: 1,
          opacity: 0.4,
          shadow: {
            blur: 5,
            color: {
              value: cor("--brand-ink"),
            },
            enable: false,
          },
          triangles: {
            enable: false,
            frequency: 1,
          },
          width: 1,
          warp: false,
        },
        repulse: {
          value: 0,
          enabled: false,
          distance: 1,
          duration: 1,
          factor: 1,
          speed: 1,
        },
      },
      pauseOnBlur: true,
      pauseOnOutsideViewport: true,
      responsive: [],
      smooth: false,
      style: {},
      themes: [],
      zLayers: 100,
      name: "Nasa",
      motion: {
        disable: false,
        reduce: {
          factor: 4,
          value: true,
        },
      },
    }),
    [theme] // Re-calc when theme changes
  );

  const containerDivRef = useRef<HTMLDivElement>(null);
  const engineContainerRef = useRef<Container | null>(null);

  const particlesLoaded = async (container?: Container): Promise<void> => {
    if (container) {
      engineContainerRef.current = container;
    }
  };

  // Audio visualizer effect - Stars bounce with the beat
  useEffect(() => {
    if (!analyser || !isPlaying || !engineContainerRef.current) return;

    let animationFrameId: number;
    const dataArray = new Uint8Array(analyser.frequencyBinCount);

    // Beat detection state
    const bassHistory: number[] = [];
    const HISTORY_SIZE = 20; // ~0.33s at 60fps (faster response)
    let lastBeatTime = 0;
    const BEAT_COOLDOWN = 80; // ms between beats (faster for electronic music)

    // Store particle-specific data with physics - each star has unique personality
    const particleData = new WeakMap<object, {
      // Personality traits (set once per particle)
      jumpStrength: number;      // How high it jumps (0.1 to 2.5)
      stiffness: number;         // How fast it returns (0.05 to 0.25)
      damping: number;           // How bouncy (0.7 to 0.92)
      beatSensitivity: number;   // Bass threshold to react (0.08 to 0.25)
      reactionDelay: number;     // Frames to wait after beat (0 to 8)
      phase: number;
      // Physics state
      offsetY: number;
      velocityY: number;
      pendingBeatFrames: number; // Countdown for delayed reaction
      pendingBeatIntensity: number;
      // Original velocity storage
      originalVelX: number | null;
      originalVelY: number | null;
      // Track applied offset
      lastOffsetY: number;
    }>();

    // Base physics constants (will be varied per particle)
    const BASE_IMPULSE = 45; // Stronger impulse for more dramatic jumps

    const render = () => {
      if (!engineContainerRef.current) {
        animationFrameId = requestAnimationFrame(render);
        return;
      }

      const now = performance.now();
      const nowSec = now / 1000;

      // 1. Get audio frequency data
      analyser.getByteFrequencyData(dataArray);

      // Bass energy (bins 0-10 for sub-bass + bass)
      let bassSum = 0;
      for (let i = 0; i < 10; i++) bassSum += dataArray[i];
      const bass = bassSum / (10 * 255);

      // Mid frequencies for additional reactivity
      let midSum = 0;
      for (let i = 10; i < 50; i++) midSum += dataArray[i];
      const mid = midSum / (40 * 255);

      // 2. Beat detection - compare current bass to recent average
      bassHistory.push(bass);
      if (bassHistory.length > HISTORY_SIZE) bassHistory.shift();

      const avgBass = bassHistory.reduce((a, b) => a + b, 0) / bassHistory.length;
      // Much more sensitive thresholds for system audio capture
      const beatThreshold = Math.max(0.04, avgBass * 1.15); // Lower threshold
      const isBeat = bass > beatThreshold && bass > 0.03 && (now - lastBeatTime) > BEAT_COOLDOWN;

      if (isBeat) {
        lastBeatTime = now;
      }

      // Energy level for continuous movement (0-1)
      const energy = Math.min(1, (bass * 2 + mid) / 1.5);

      // 3. Get particles
      const container = engineContainerRef.current as any;
      let particles: any[] = [];

      if (container.particles) {
        if (container.particles.array && Array.isArray(container.particles.array)) {
          particles = container.particles.array;
        } else if (typeof container.particles.filter === 'function') {
          particles = container.particles.filter(() => true);
        } else if (container.particles.quadTree) {
          const canvas = container.canvas?.element;
          if (canvas) {
            particles = container.particles.quadTree.query({
              position: { x: canvas.width / 2, y: canvas.height / 2 },
              radius: Math.max(canvas.width, canvas.height)
            });
          }
        }
      }

      // 4. Apply physics to each particle
      particles.forEach((p: any) => {
        if (!p || !p.position) return;

        // Initialize particle data with unique personality
        if (!particleData.has(p)) {
          // Create unique personality for this star
          const r1 = Math.random();
          const r2 = Math.random();
          const r3 = Math.random();

          // Some stars are "big jumpers", others barely move
          // Using pow to create more variety (more extreme values)
          const jumpType = Math.pow(Math.random(), 0.7); // 0 to 1, skewed toward higher

          particleData.set(p, {
            // Personality: wide range of behaviors
            jumpStrength: 0.3 + jumpType * 3.0,         // 0.3 to 3.3 (even bigger range!)
            stiffness: 0.08 + r1 * 0.20,                // 0.08 to 0.28 (slow to snappy)
            damping: 0.75 + r2 * 0.17,                  // 0.75 to 0.92 (wobbly to tight)
            beatSensitivity: 0.01 + r3 * 0.08,          // 0.01 to 0.09 (very sensitive!)
            reactionDelay: Math.floor(Math.random() * 6), // 0 to 5 frames delay (faster wave)
            phase: Math.random() * Math.PI * 2,
            // Physics state
            offsetY: 0,
            velocityY: 0,
            pendingBeatFrames: 0,
            pendingBeatIntensity: 0,
            // Original velocity storage
            originalVelX: null,
            originalVelY: null,
            lastOffsetY: 0
          });
        }

        const data = particleData.get(p)!;

        // === PAUSE HORIZONTAL MOVEMENT ===
        const velObj = p.velocity;
        if (velObj) {
          if (data.originalVelX === null) {
            data.originalVelX = velObj.x ?? 0;
            data.originalVelY = velObj.y ?? 0;
          }
          velObj.x = 0;
          velObj.y = (data.originalVelY ?? 0) * 0.1;
        }

        // === BEAT IMPULSE with varying intensity ===
        // The stronger the beat (bass peak vs average), the stronger the jump
        if (isBeat && bass > data.beatSensitivity) {
          // Calculate beat intensity: how much stronger is this beat vs average?
          const beatIntensity = Math.min(3, (bass / Math.max(0.01, avgBass))); // 1 to 3x multiplier

          if (data.reactionDelay === 0) {
            // Impulse varies with beat intensity AND bass strength
            const impulse = -BASE_IMPULSE * beatIntensity * bass * data.jumpStrength;
            data.velocityY += impulse;
          } else {
            data.pendingBeatFrames = data.reactionDelay;
            data.pendingBeatIntensity = bass * beatIntensity; // Store intensity too
          }
        }

        // Process delayed beat reactions
        if (data.pendingBeatFrames > 0) {
          data.pendingBeatFrames--;
          if (data.pendingBeatFrames === 0) {
            const impulse = -BASE_IMPULSE * data.pendingBeatIntensity * data.jumpStrength;
            data.velocityY += impulse;
            data.pendingBeatIntensity = 0;
          }
        }

        // === CONTINUOUS MICRO-MOVEMENT ===
        // Stars always have subtle movement - never completely still
        const microMovement = Math.sin(nowSec * 2 + data.phase) * 0.3 * data.jumpStrength;

        // Energy-based floating (follows the music volume)
        const energyFloat = -energy * 12 * data.jumpStrength;

        // === SPRING PHYSICS ===
        // Target position combines energy float and micro movement
        const targetY = energyFloat + microMovement;
        const springForce = (targetY - data.offsetY) * data.stiffness * 1.2;
        data.velocityY += springForce;
        data.velocityY *= data.damping;

        // Update offset
        data.offsetY += data.velocityY;

        // Clamp to prevent extreme values
        data.offsetY = Math.max(-120, Math.min(120, data.offsetY));

        // Apply position offset
        p.position.y -= data.lastOffsetY; // Remove previous
        p.position.y += data.offsetY; // Add current
        data.lastOffsetY = data.offsetY;

        // === SIZE - Keep original, no pulse ===
        // Stars maintain their original size

        // === OPACITY/GLOW (subtle) ===
        const opacityObj = p.opacity;
        if (opacityObj && typeof opacityObj === 'object' && 'value' in opacityObj) {
          const baseOpacity = (p as any)._audioBaseOpacity ?? opacityObj.value ?? 0.5;
          if ((p as any)._audioBaseOpacity === undefined) (p as any)._audioBaseOpacity = baseOpacity;

          // Subtle twinkle only - no dramatic glow changes
          const twinkle = Math.sin(nowSec * 2.5 + data.phase) * 0.12;
          const energyGlow = energy * 0.15; // Very subtle

          const newOpacity = Math.min(0.85, Math.max(0.25, baseOpacity + twinkle + energyGlow));
          opacityObj.value = newOpacity;
        }
      });

      animationFrameId = requestAnimationFrame(render);
    };

    render();

    return () => {
      cancelAnimationFrame(animationFrameId);

      // Restore original velocities when music stops
      const container = engineContainerRef.current as any;
      if (container?.particles?.array) {
        container.particles.array.forEach((p: any) => {
          if (!p) return;
          const data = particleData.get(p);
          if (data && p.velocity) {
            p.velocity.x = data.originalVelX ?? p.velocity.x;
            p.velocity.y = data.originalVelY ?? p.velocity.y;
          }
          // Reset position offset
          if (data && p.position) {
            p.position.y -= data.lastOffsetY;
          }
        });
      }
    };
  }, [analyser, isPlaying]);

  if (init) {
    return (
      <div
        ref={containerDivRef}
        className="fixed inset-0 pointer-events-none z-base"
      >
        <Particles
          id="tsparticles"
          key={theme}
          particlesLoaded={particlesLoaded}
          options={options}
        />
      </div>
    );
  }

  return <></>;
};
