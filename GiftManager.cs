using UnityEngine;
using System;

public class GiftManager : MonoBehaviour {

	// A singleton instance of this class
	private static GiftManager instance;
	public static GiftManager Instance {
		get {
			if (instance == null) instance = GameObject.FindObjectOfType<GiftManager>();
			return instance;
		}
	}

	private string savedTime;
	private int giftSeed = 0;
	private string timeFormat = "MM dd, yyyy HH:mm";
	private string currentTime { get { return DateTime.Now.ToString(timeFormat); } }

	void Awake()
	{
		giftSeed = PlayerPrefs.GetInt("GiftSeed");

		if(PlayerPrefs.HasKey("TimeSinceLastGift"))
			savedTime = PlayerPrefs.GetString("TimeSinceLastGift");
		else
		{
			TimeSpan span = new TimeSpan(0, 1, 0);
			savedTime = DateTime.Now.Subtract(span).ToString(timeFormat);
		}
	}
	
	public bool CanShowGift()
	{
		//Debug.Log (string.Format("Gift Time: {0}, Last Gift: {1}", GetGiftTime(), TimeSince(savedTime)));

		if(TimeSince(savedTime) > GetGiftTime())
		{
			PlayerPrefs.SetString("TimeSinceLastGift", savedTime);
			return true;
		}

		return false;
	}
	
	public float GetGiftTime()
	{
		return Mathf.Clamp(Mathf.RoundToInt(Mathf.Exp(giftSeed)), 120, 21600);
	}

	public void IncreaseGiftSeed()
	{
		savedTime = currentTime;
		if(giftSeed < 21)
		{
			giftSeed++;
			PlayerPrefs.SetInt("GiftSeed", giftSeed);
		}
	}

	public int HoursUntilGift()
	{
		return Mathf.FloorToInt((GetGiftTime() - TimeSince(savedTime)) / 3600);
	}

	public int MinutesUntilGift()
	{
		//Debug.Log (string.Format ("Gift Time: {0}, TimeSince: {1}, Mod360: {2}", GetGiftTime(), TimeSince(savedTime), (GetGiftTime() - TimeSince (savedTime)) % 3600));
		return Mathf.Max(1, Mathf.FloorToInt( ( (GetGiftTime() - TimeSince(savedTime)) % 3600 ) / 60));
	}

	private float TimeSince(string lastTime)
	{
		return (float)DateTime.Now.Subtract(DateTime.Parse(lastTime)).TotalSeconds;
	}
}