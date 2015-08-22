using UnityEngine;
using System.Collections;
using System.Collections.Generic;

public class AudioManager : MonoBehaviour {

	// A singleton instance of this class
	private static AudioManager instance;
	public static AudioManager Instance {
		get {
			if (instance == null) instance = GameObject.FindObjectOfType<AudioManager>();
			return instance;
		}
	}
	
	#region Properties
	
	public AudioClip[] soundClips;
	public AudioClip[] musicClips;

	[HideInInspector]public AudioClip slurpSound;
	[HideInInspector]public AudioClip selectSound;
	[HideInInspector]public AudioClip squishSound;
	[HideInInspector]public AudioClip grabSound;
	[HideInInspector]public AudioClip hurtSound;
	[HideInInspector]public AudioClip missSound;
	[HideInInspector]public AudioClip awakeSound;
	[HideInInspector]public AudioClip fallSound;
	[HideInInspector]public AudioClip flySound;
	[HideInInspector]public AudioClip newSound;
	[HideInInspector]public AudioClip blinkSound;
	[HideInInspector]public AudioClip highScoreSound;
	[HideInInspector]public AudioClip base10Sound;
	[HideInInspector]public AudioClip crumbleSound;
	[HideInInspector]public AudioClip crumbleShortSound;
	[HideInInspector]public AudioClip boilVoiceSound;
	[HideInInspector]public AudioClip perfectVoiceSound;
	[HideInInspector]public AudioClip okVoiceSound;
	[HideInInspector]public AudioClip greatVoiceSound;
	[HideInInspector]public AudioClip splashSound;
	[HideInInspector]public AudioClip holdOnVoiceSound;
    [HideInInspector]public AudioClip leafSound;

	private float soundVolume = 1f;

	private bool musicOnAwakeLoop = true;
	private float musicOnAwakeVolume = .7f;

	private int channelCount = 2;
//	private float crossFadeSeconds = 3f;

	private AudioSource managerSource;
	public AudioSource ManagerSource { get { 
			if(managerSource == null) managerSource = Camera.main.GetComponent<AudioSource>();
			return managerSource; 
		} }
	private GameObject[] channels;
	private int channelIndex = 0;
	private bool channelIndexRev = false;
	private bool musicClipLoop;
	private float musicClipVolume;

	private bool isCrossFading = false;
	private bool isFadingOut = false;
	private bool isFadingIn = false;
	private AudioSource caIn;
	private AudioSource caOut;
//	private float fadeInMaxVolume;
//	private float fadeOutMaxVolume;

	private float fadeAmount = .01f;

	private Transform _transform;
	
	#endregion Properties
	
	#region Component Segments
	
	void Awake()
	{
		if(GameObject.FindObjectsOfType<AudioManager>().Length > 1)
			Destroy (gameObject);
		else
			DontDestroyOnLoad(gameObject);

		_transform = transform;

		channels = new GameObject[channelCount];
		for(int i = 0; i < channelCount; i++)
		{
			channels[i] = _transform.FindChild("Channel" + (i + 1)).gameObject;
		}
		SetUpSounds();
	}

	void Update()
	{
//		if(isCrossFading)
//		{
//			caIn.volume = fadeInMaxVolume * Mathf.Clamp01(caIn.volume / fadeInMaxVolume + ((crossFadeSeconds / 10) * Time.deltaTime));
//			caOut.volume = fadeOutMaxVolume * Mathf.Clamp01(caOut.volume / fadeOutMaxVolume - (( crossFadeSeconds / 10) * Time.deltaTime));

			//Stop the music if it reaches 0 volume
//			if(caIn.volume == fadeInMaxVolume && caOut.volume == 0)
//			{
//				caOut.Stop();
//				isCrossFading = false;
//			}
//		}
		if(isFadingOut && channels[channelIndex].GetComponent<AudioSource>().volume > 0)
		{
			channels[channelIndex].GetComponent<AudioSource>().volume -= fadeAmount;

			if(channels[channelIndex].GetComponent<AudioSource>().volume == 0)
				channels[channelIndex].GetComponent<AudioSource>().Pause();
		}
		else if(isFadingIn && channels[channelIndex].GetComponent<AudioSource>().volume < 1)
		{
			channels[channelIndex].GetComponent<AudioSource>().volume += fadeAmount;
		}
	}
	
	#endregion Component Segments
	
	#region Functions
	
	//Plays sound at player
	public void Play (AudioClip clip = null, AudioSource source = null)
	{
		if(source == null) source = ManagerSource;

        if (clip == null)
        {
            source.Play();
        }
        else
        {
            source.PlayOneShot(clip, soundVolume);
        }
	}

	public void PlayIn(float delay, AudioClip clip, AudioSource source = null)
	{
		StartCoroutine(PlayWithDelay(delay, clip, source));
	}
	
	public void StartMusic(bool isStarting = false, int newIndex = 0)
	{
		if(!VariableManager.Instance.IsPlayingMusic) return;

        if (isFadingOut)
        {
            FadeInMusic();
        }

        if (isStarting)
        {
            SetMusicClipLoop(musicOnAwakeLoop);
            SetMusicClipVolume(musicOnAwakeVolume);
        }

//		int newIndex = 0;
	//	do
		//{
			// newIndex = Random.Range(0, musicClips.Length);
		//} while (channels[channelIndex].GetComponent<AudioSource>().isPlaying && musicClips[newIndex] != channels[channelIndex].GetComponent<AudioSource>().clip);

		PlayMusicClip(newIndex);

	//	StartCoroutine(CheckForMusicEnd());
	}

	public void FadeOutMusic()
	{
		isCrossFading = false;
		isFadingOut = true;
		isFadingIn = false;
	}

	#region Private Functions
	
	private void SetUpSounds()
	{
		blinkSound = ReturnClip("Blink");
		slurpSound = ReturnClip("Slurp");
		selectSound = ReturnClip("Select");
		squishSound = ReturnClip("Squish");
		grabSound = ReturnClip("Grab");
		hurtSound = ReturnClip("Hurt");
		missSound = ReturnClip("Miss");
		awakeSound = ReturnClip("Awake");
		fallSound = ReturnClip("Fall");
		flySound = ReturnClip("Flys");
		newSound = ReturnClip("New");
		highScoreSound = ReturnClip("HighScore");
		base10Sound = ReturnClip("Base10");
		crumbleSound = ReturnClip("Crumble");
		crumbleShortSound = ReturnClip("CrumbleShort");
		boilVoiceSound = ReturnClip("BoilAFrogVO");
		perfectVoiceSound = ReturnClip("PerfectVO");
		okVoiceSound = ReturnClip("OKVO");
		greatVoiceSound = ReturnClip("GreatVO");
		splashSound = ReturnClip ("Splash");
		holdOnVoiceSound = ReturnClip("HoldOnVO");
        leafSound = ReturnClip("LeafSound");
	}

	private void FadeInMusic()
	{
		if(!channels[channelIndex].GetComponent<AudioSource>().isPlaying) 
			channels[channelIndex].GetComponent<AudioSource>().Play();
		isFadingIn = true;
		isFadingOut = false;
	}

	private void SetMusicClipLoop(bool loop)
	{
		musicClipLoop = loop;
	}

	private void SetMusicClipVolume(float volume)
	{
		musicClipVolume = volume;
	}

	private bool PlayMusicClip(int clipIndex)
	{
		if(clipIndex < 0)
			return false;

		AudioSource caCurrent = channels[channelIndex].GetComponent<AudioSource>();
		if(caCurrent.clip != null && caCurrent.isPlaying) // Music is playing on this channel
		{
			if(caCurrent.clip == musicClips[clipIndex]) // Triggered clip is already playing
			{
				caCurrent.loop = musicClipLoop;
				return true;
			}

			if(isCrossFading) // Music is already crossfading
			{
				if(caOut.clip == musicClips[clipIndex]) // crossfading clip is the same one we need to fiade in now
				{
					caCurrent = caOut;
					caOut = caIn;
					caIn = caCurrent;
//					fadeOutMaxVolume = fadeInMaxVolume;
//					fadeInMaxVolume = musicClipVolume;
					caIn.loop = musicClipLoop;
					channelIndexRev = !channelIndexRev;
					channelIndex = GetNewChannelIndex();
					return true;
				}

				caOut.volume = 0;
				caOut.Stop ();
			}
			AudioSource caNew = channels[GetNewChannelIndex()].GetComponent<AudioSource>();
			caNew = SetChannelToPlay(caNew, clipIndex, 0);
			isCrossFading = true;
			caIn = caNew;
			caOut = caCurrent;
//			fadeInMaxVolume = musicClipVolume;
//			fadeOutMaxVolume = caCurrent.volume;channelIndex = GetNewChannelIndex();
			return true;
		}
		else //No music is playing on this channel
		{
			SetChannelToPlay(caCurrent, clipIndex, musicClipVolume);
			return true;
		}
	}

	private int GetNewChannelIndex()
	{
        return channelIndex == 0 ? 1 : 0;
	}

	private AudioSource SetChannelToPlay(AudioSource channel, int index, float volume)
	{
		channel.clip = musicClips[index];
		channel.loop = musicClipLoop;
		channel.volume = volume;
		channel.Play();
		return channel;
	}

	private AudioClip ReturnClip(string sound, AudioClip[] soundSource = null)
	{
		if(soundSource == null) soundSource = soundClips;

		for(int i = 0; i < soundSource.Length; i++)
		{
			if(soundSource[i].name == sound)
				return soundSource[i];
		}
		return null;
	}
	
	//Used to play a random sound from an array of Audioclips at source
	private void PlayRandomAudio(string sound, AudioSource source) 
	{
		List<AudioClip> clips = new List<AudioClip>();
		for(int i=0; i< soundClips.Length; i++)
			if(soundClips[i].name == sound) clips.Add(soundClips[i]);

		source.loop = false;
		source.clip = clips[Random.Range (0, clips.Count)];
		source.Play ();
	}

	private IEnumerator PlayWithDelay(float delay, AudioClip clip, AudioSource source)
	{
		yield return new WaitForSeconds(delay);
		Play(clip, source);
	}

	#endregion Private Functions

	#endregion Functions
}
