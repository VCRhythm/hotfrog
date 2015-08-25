using UnityEngine;

public class AudioPlayer : MonoBehaviour {

    private bool isFadingOut = false;
    private bool isFadingIn = false;
    private bool musicOnAwakeLoop = true;
    private float musicOnAwakeVolume = .7f;
    private VariableManager variableManager;
    private int channelCount = 2;
    private GameObject[] channels;
    private int channelIndex = 0;
    private bool channelIndexRev = false;
    private bool musicClipLoop;
    private float musicClipVolume;

    private bool isCrossFading = false;
    private AudioSource caIn;
    private AudioSource caOut;
    //	private float fadeInMaxVolume;
    //	private float fadeOutMaxVolume;

    private float fadeAmount = .01f;

    void Awake()
    {
        channels = new GameObject[channelCount];
        for (int i = 0; i < channelCount; i++)
        {
            channels[i] = transform.FindChild("Channel" + (i + 1)).gameObject;
        }

        variableManager = GetComponent<VariableManager>();
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
        if (isFadingOut && channels[channelIndex].GetComponent<AudioSource>().volume > 0)
        {
            channels[channelIndex].GetComponent<AudioSource>().volume -= fadeAmount;

            if (channels[channelIndex].GetComponent<AudioSource>().volume == 0)
                channels[channelIndex].GetComponent<AudioSource>().Pause();
        }
        else if (isFadingIn && channels[channelIndex].GetComponent<AudioSource>().volume < 1)
        {
            channels[channelIndex].GetComponent<AudioSource>().volume += fadeAmount;
        }
    }

    public void StartMusic(bool isStarting = false, int newIndex = 0)
    {
        if (!variableManager.IsPlayingMusic) return;

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

    private void FadeInMusic()
    {
        if (!channels[channelIndex].GetComponent<AudioSource>().isPlaying)
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
        if (clipIndex < 0)
            return false;

        AudioSource caCurrent = channels[channelIndex].GetComponent<AudioSource>();
        if (caCurrent.clip != null && caCurrent.isPlaying) // Music is playing on this channel
        {
            if (caCurrent.clip == AudioManager.Instance.musicClips[clipIndex]) // Triggered clip is already playing
            {
                caCurrent.loop = musicClipLoop;
                return true;
            }

            if (isCrossFading) // Music is already crossfading
            {
                if (caOut.clip == AudioManager.Instance.musicClips[clipIndex]) // crossfading clip is the same one we need to fiade in now
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
                caOut.Stop();
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
        channel.clip = AudioManager.Instance.musicClips[index];
        channel.loop = musicClipLoop;
        channel.volume = volume;
        channel.Play();
        return channel;
    }

    public void FadeOutMusic()
    {
        isCrossFading = false;
        isFadingOut = true;
        isFadingIn = false;
    }

}
