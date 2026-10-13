let content = fragmentElement.querySelector('.video');
let videoContainer = fragmentElement.querySelector('.video-container');
let errorMessage = fragmentElement.querySelector('.error-message');
let loadingIndicator = fragmentElement.querySelector('.loading-animation');
let videoMask = fragmentElement.querySelector('.video-mask');
let urlElement = fragmentElement.querySelector('[data-lfr-editable-id="video-url"]');

const height = configuration.videoHeight
	? configuration.videoHeight.replace('px', '')
	: '315';
const width = configuration.videoWidth
	? configuration.videoWidth.replace('px', '')
	: '560';

function resize() {
	const scrollPosition = {
		left: window.scrollX,
		top: window.scrollY,
	};

	content.style.height = '';
	content.style.width = '';

	requestAnimationFrame(function () {
		try {
			const boundingClientRect = content.getBoundingClientRect();
			const contentWidth = width === '100%' ? boundingClientRect.width : (width || boundingClientRect.width);
			const contentHeight = height === 'auto' ? contentWidth * 0.5625 : (height || contentWidth * 0.5625);

			content.style.height = contentHeight + 'px';
			content.style.width = contentWidth + 'px';

			window.scrollTo(scrollPosition);
		}
		catch (error) {
			window.removeEventListener('resize', resize);
		}
	});
}

function showVideo() {
	if (videoContainer) {
		videoContainer.removeAttribute('aria-hidden');
	}
	if (errorMessage && errorMessage.parentElement) {
		errorMessage.parentElement.removeChild(errorMessage);
	}
	if (loadingIndicator && loadingIndicator.parentElement) {
		loadingIndicator.parentElement.removeChild(loadingIndicator);
	}
	if (layoutMode !== 'edit' && videoMask && videoMask.parentElement) {
		videoMask.parentElement.removeChild(videoMask);
	}

	window.addEventListener('resize', resize);
	resize();
}

function showError() {
	if (layoutMode === 'edit') {
		if (errorMessage) {
			errorMessage.removeAttribute('hidden');
		}
		if (videoContainer && videoContainer.parentElement) {
			videoContainer.parentElement.removeChild(videoContainer);
		}
		if (loadingIndicator && loadingIndicator.parentElement) {
			loadingIndicator.parentElement.removeChild(loadingIndicator);
		}
	}
	else {
		if (fragmentElement && fragmentElement.parentElement) {
			fragmentElement.parentElement.removeChild(fragmentElement);
		}
	}
}

const rawProvider = {
	getParameters: function (url) {
		return {url: url};
	},

	showVideo: function (parameters) {
		const video = document.createElement('video');
		const source = document.createElement('source');

		// Clean video source URL from ?download=true or &download=true to support Range requests
		const cleanUrl = parameters.url
			.replace(/[?&]videoThumbnail=1/gi, '')
			.replace(/[?&]download=true/gi, '');

		source.src = cleanUrl;

		video.autoplay = configuration.autoPlay;
		video.controls = !configuration.hideControls;
		video.loop = configuration.loop;
		video.muted = configuration.mute;
		video.playsInline = true;

		video.style.height = '100%';
		video.style.width = '100%';

		video.appendChild(source);
		videoContainer.appendChild(video);
		showVideo();
	},
};

const youtubeProvider = {
	getParameters: function (url) {
		const start = url.searchParams.get('start');

		if (['www.youtube.com', 'youtube.com'].includes(url.hostname)) {
			const videoId = url.searchParams.get('v');

			if (videoId) {
				return {
					start: start,
					videoId: videoId,
				};
			}
		}
		else if (['www.youtu.be', 'youtu.be'].includes(url.hostname)) {
			const videoId = url.pathname.substr(1);

			if (videoId) {
				return {
					start: start,
					videoId: videoId,
				};
			}
		}
	},

	showVideo: function (parameters) {
		const handleAPIReady = function () {
			const player = new YT.Player(videoContainer, {
				events: {
					onReady: function () {
						if (configuration.mute) {
							player.mute();
						}
						showVideo();
					},
				},
				height: height,
				playerVars: {
					autoplay: configuration.autoPlay ? 1 : 0,
					controls: configuration.hideControls ? 0 : 1,
					loop: configuration.loop ? 1 : 0,
					playlist: configuration.loop
						? parameters.videoId
						: undefined,
					start: !parameters.start ? 0 : parameters.start,
				},
				videoId: parameters.videoId,
				width: width,
			});
		};

		if ('YT' in window) {
			handleAPIReady();
		}
		else {
			const oldCallback = window.onYouTubeIframeAPIReady;

			window.onYouTubeIframeAPIReady = function () {
				if (oldCallback) {
					oldCallback();
				}
				handleAPIReady();
			};

			const tag = document.createElement('script');
			tag.src = 'https://www.youtube.com/iframe_api';
			const firstScriptTag = document.getElementsByTagName('script')[0];
			firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
		}
	},
};

function init() {
	// 1. Check if Liferay injected a native video element directly (common when mapping a Media/Video field)
	const injectedVideo = urlElement ? urlElement.querySelector('video') : null;
	
	if (injectedVideo) {
		console.log("Injected video element detected from Liferay mapping. Integrating configurations.");
		
		// Clean video source URLs from ?download=true or &download=true to support Range requests
		if (injectedVideo.src) {
			injectedVideo.src = injectedVideo.src
				.replace(/[?&]videoThumbnail=1/gi, '')
				.replace(/[?&]download=true/gi, '');
		}
		const sources = injectedVideo.querySelectorAll('source');
		sources.forEach(srcEl => {
			if (srcEl.src) {
				srcEl.src = srcEl.src
					.replace(/[?&]videoThumbnail=1/gi, '')
					.replace(/[?&]download=true/gi, '');
			}
		});

		// Inherit configurations from configuration.json
		injectedVideo.autoplay = configuration.autoPlay;
		injectedVideo.loop = configuration.loop;
		injectedVideo.muted = configuration.mute;
		if (configuration.hideControls) {
			injectedVideo.removeAttribute('controls');
			injectedVideo.removeAttribute('controlslist');
		} else {
			injectedVideo.setAttribute('controls', '');
			injectedVideo.setAttribute('controlslist', 'nodownload');
		}
		injectedVideo.setAttribute('playsinline', '');
		injectedVideo.style.height = '100%';
		injectedVideo.style.width = '100%';
		
		// Move/Append the video element directly into our styled container
		videoContainer.innerHTML = '';
		videoContainer.appendChild(injectedVideo);
		showVideo();
		return;
	}

	// 2. Fallback to parsing as plain text URL (e.g. YouTube or raw file link)
	const urlString = urlElement ? urlElement.textContent.trim() : '';
	
	if (urlString) {
		try {
			// Try to parse as URL
			let parsedUrlString = urlString;
			if (!urlString.startsWith('http://') && !urlString.startsWith('https://') && !urlString.startsWith('/')) {
				parsedUrlString = 'https://' + urlString;
			}
			
			if (parsedUrlString.startsWith('/')) {
				// Relative URL representing a Document / Media file
				rawProvider.showVideo({url: parsedUrlString});
			} else {
				const url = new URL(parsedUrlString);
				let parameters = youtubeProvider.getParameters(url);
				if (parameters) {
					youtubeProvider.showVideo(parameters);
				} else {
					parameters = rawProvider.getParameters(parsedUrlString);
					rawProvider.showVideo(parameters);
				}
			}
		}
		catch (e) {
			console.warn("Failed to parse video URL, falling back to direct video tag:", e);
			if (urlString.startsWith('/') || urlString.startsWith('http')) {
				rawProvider.showVideo({url: urlString});
			} else {
				showError();
			}
		}
	}
	else {
		showError();
	}
}

// Support live re-rendering inside layout page editor when mapped fields change
if (layoutMode === 'edit' && urlElement) {
	const observer = new MutationObserver(function() {
		// Clear container and re-initialize
		if (videoContainer) {
			videoContainer.innerHTML = '';
		}
		init();
	});
	observer.observe(urlElement, { characterData: true, childList: true, subtree: true });
}

init();
