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

//	private float crossFadeSeconds = 3f;

	private AudioSource managerSource;
	public AudioSource ManagerSource { get { 
			if(managerSource == null) managerSource = Camera.main.GetComponent<AudioSource>();
			return managerSource; 
		} }

    private AudioPlayer[] audioPlayers;

	#endregion Properties
	
	#region Component Segments
	
	void Awake()
	{
		if(FindObjectsOfType<AudioManager>().Length > 1)
			Destroy (gameObject);
		else
			DontDestroyOnLoad(gameObject);

		SetUpSounds();

        audioPlayers = FindObjectsOfType<AudioPlayer>();
	}
	
	#endregion Component Segments
	
	#region Functions
	
	//Plays sound at player
	public void PlayForAll (AudioClip clip = null, AudioSource source = null)
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
        for(int i=0; i<audioPlayers.Length; i++)
        {
            audioPlayers[i].StartMusic(isStarting, newIndex);
        }
	}

    public void FadeOutMusic()
    {
        for (int i = 0; i < audioPlayers.Length; i++)
        {
            audioPlayers[i].FadeOutMusic();
        }
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
		PlayForAll(clip, source);
	}

	#endregion Private Functions

	#endregion Functions
}
