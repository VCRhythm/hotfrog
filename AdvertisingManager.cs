using UnityEngine;
using UnityEngine.Advertisements;

public class AdvertisingManager : MonoBehaviour {

	// A singleton instance of this class
	private static AdvertisingManager instance;
	public static AdvertisingManager Instance {
		get {
			if (instance == null) instance = GameObject.FindObjectOfType<AdvertisingManager>();
			return instance;
		}
	}

	public bool IsReady { get { return Advertisement.isReady() && (Time.time - lastAdvertisementTime > 60f || lastAdvertisementTime == 0); } }

	private float lastAdvertisementTime = 0;

	void Awake()
	{
		if(Advertisement.isSupported)
		{
			Advertisement.allowPrecache = true;
			Advertisement.Initialize("131627335");
		}
	}

	public void PlayAdvertisement()
	{
		Advertisement.Show(null, new ShowOptions {
			pause = true,
			resultCallback = ShowResult => {
			}
		});

		lastAdvertisementTime = Time.time;
		MenuManager.Instance.SpawnGiftFlys(false);
	}
}