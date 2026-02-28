(() => {
    'use strict';

    const progressFill = document.getElementById('progressFill');
    const progressGlow = document.getElementById('progressGlow');
    const progressText = document.getElementById('progressText');
    const statusText = document.getElementById('statusText');
    const speedLinesContainer = document.getElementById('speedLines');
    const particlesContainer = document.getElementById('particles');

    let currentProgress = 0;
    let targetProgress = 0;

    // Speed lines
    function createSpeedLines() {
        for (let i = 0; i < 15; i++) {
            const line = document.createElement('div');
            line.classList.add('speed-line');
            line.style.top = Math.random() * 100 + '%';
            line.style.width = (100 + Math.random() * 300) + 'px';
            line.style.setProperty('--duration', (3 + Math.random() * 5) + 's');
            line.style.animationDelay = Math.random() * 5 + 's';
            speedLinesContainer.appendChild(line);
        }
    }

    // Particles
    function createParticles() {
        for (let i = 0; i < 30; i++) {
            const particle = document.createElement('div');
            particle.classList.add('particle');
            particle.style.left = Math.random() * 100 + '%';
            particle.style.top = Math.random() * 100 + '%';
            particle.style.setProperty('--duration', (4 + Math.random() * 8) + 's');
            particle.style.setProperty('--tx', (Math.random() * 40 - 20) + 'px');
            particle.style.setProperty('--ty', (Math.random() * 40 - 20) + 'px');
            particle.style.animationDelay = Math.random() * 4 + 's';
            particlesContainer.appendChild(particle);
        }
    }

    function updateProgress() {
        if (currentProgress < targetProgress) {
            currentProgress += (targetProgress - currentProgress) * 0.08;
            if (targetProgress - currentProgress < 0.5) currentProgress = targetProgress;
        }

        const pct = Math.min(Math.round(currentProgress), 100);
        progressFill.style.width = pct + '%';
        progressGlow.style.left = pct + '%';
        progressText.textContent = pct + '%';

        requestAnimationFrame(updateProgress);
    }

    // FiveM loading screen handler messages
    const handlers = {
        startInitFunction(data) {
            if (data.type === 'initFunctionInvoking') {
                statusText.textContent = 'Loading game...';
                targetProgress = Math.max(targetProgress, 20);
            }
        },

        startInitFunctionOrder(data) {
            if (data.type === 'initFunctionInvoking') {
                const order = data.order;
                if (order >= 0 && order < 10) {
                    targetProgress = Math.max(targetProgress, 20 + order * 5);
                }
            }
        },

        startDataFileEntries(data) {
            statusText.textContent = 'Loading data files...';
            targetProgress = Math.max(targetProgress, 60);
        },

        performMapLoadFunction(data) {
            statusText.textContent = 'Loading map...';
            targetProgress = Math.max(targetProgress, 75);
        },

        onLogLine(data) {
            if (data.message) {
                statusText.textContent = data.message.substring(0, 80);
            }
        }
    };

    window.addEventListener('message', (event) => {
        const handler = handlers[event.data.eventName];
        if (handler) {
            handler(event.data);
        }
    });

    // Simulate initial progress for connection phase
    let simulatedProgress = 0;
    const simulateInterval = setInterval(() => {
        simulatedProgress += 0.3;
        if (simulatedProgress >= 15) {
            clearInterval(simulateInterval);
        }
        targetProgress = Math.max(targetProgress, simulatedProgress);
    }, 100);

    // When FiveM signals loading is done
    window.addEventListener('message', (event) => {
        if (event.data.eventName === 'loadProgress') {
            const loadFraction = event.data.loadFraction;
            targetProgress = Math.max(targetProgress, loadFraction * 100);
        }
    });

    // Background slideshow
    const slides = document.querySelectorAll('.bg-slide');
    let currentSlide = 0;

    function cycleSlides() {
        slides[currentSlide].classList.remove('active');
        currentSlide = (currentSlide + 1) % slides.length;
        slides[currentSlide].classList.add('active');
    }

    if (slides.length > 1) {
        setInterval(cycleSlides, 6000);
    }

    createSpeedLines();
    createParticles();
    requestAnimationFrame(updateProgress);
})();
