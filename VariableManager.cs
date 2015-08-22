using UnityEngine;
using TMPro;
using UnityEngine.SocialPlatforms;

public class VariableManager : MonoBehaviour {

	// A singleton instance of this class
	private static VariableManager instance;
	public static VariableManager Instance {
		get {
			if (instance == null) instance = GameObject.FindObjectOfType<VariableManager>();
			return instance;
		}
	}
	
	private int highScore = 0;
	public int HighScore { get { return highScore; } set { highScore = value; highScoreText.SetText("TOP: {0}", value); } }

	public bool IsPlayingMusic { get; private set; }
	public int currentFrogID = -1;

	private TextMeshProUGUI highScoreText;
	private bool hasLoadedSocial = false;

	void Awake()
	{
		Transform hud = GameObject.Find ("HUD").transform;
		highScoreText = hud.FindChild ("HighScore").GetComponent<TextMeshProUGUI>();
		currentFrogID = PlayerPrefs.GetInt("FrogID", 1);
		HighScore = PlayerPrefs.GetInt("HighScore", 0);
		IsPlayingMusic = PlayerPrefsX.GetBool("IsPlayingMusic", true);
		HUD.Instance.BugsCaught = PlayerPrefs.GetInt("Bugs", 0);

		Social.localUser.Authenticate(ProcessAuthentication);
	}
	
	public void SaveStats(int bugCount, int stepsClimbed)
	{
		SaveBugs(bugCount);
		SaveFrog();

		if(HighScore < stepsClimbed)
		{
			if(hasLoadedSocial)
				CheckForAchievement(stepsClimbed, HighScore);

			SaveHighScore(stepsClimbed);
			HighScore = stepsClimbed;
			highScoreText.color = Color.green;
		}
	}

	public void SaveSettings()
	{
		PlayerPrefsX.SetBool("IsPlayingMusic", IsPlayingMusic);
	}

	public void ToggleMusic()
	{
		AudioManager.Instance.Play(AudioManager.Instance.selectSound);
		IsPlayingMusic = !IsPlayingMusic;
	}
	
	public void SaveBugs(int bugCount)
	{
		PlayerPrefs.SetInt("Bugs", bugCount);
	}
	
	private void SaveHighScore(int stepsClimbed)
	{
		PlayerPrefs.SetInt("HighScore", stepsClimbed);
	}

	private void SaveFrog()
	{
		PlayerPrefs.SetInt("FrogID", currentFrogID);
	}

	private void ProcessAuthentication(bool success)
	{
		if(success)
		{
			Social.LoadAchievements(ProcessLoadedAchievements);
		}
	}

	private void ProcessLoadedAchievements(IAchievement[] achievements)
	{
		if(achievements.Length > 0)
			hasLoadedSocial = true;
	}

	private void CheckForAchievement(int steps, int lastSteps)
	{
		if(lastSteps < 10 && steps >= 10)
			Social.ReportProgress("10!", 100.0, (success) => {});

		if(lastSteps < 20 && steps >= 20)
			Social.ReportProgress("20!", 100.0, (success) => {});

		if(lastSteps < 30 && steps >= 30)
			Social.ReportProgress("30!", 100.0, (success) => {});

		if(lastSteps < 40 && steps >= 40)
			Social.ReportProgress("40!", 100.0, (success) => {});

		if(lastSteps < 50 && steps >= 50)
			Social.ReportProgress("50!", 100.0, (success) => {});

		if(lastSteps < 60 && steps >= 60)
			Social.ReportProgress("60!", 100.0, (success) => {});
		
		if(lastSteps < 70 && steps >= 70)
			Social.ReportProgress("70!", 100.0, (success) => {});
		
		if(lastSteps < 80 && steps >= 80)
			Social.ReportProgress("80!", 100.0, (success) => {});
		
		if(lastSteps < 90 && steps >= 90)
			Social.ReportProgress("90!", 100.0, (success) => {});
		
		if(lastSteps < 100 && steps >= 100)
			Social.ReportProgress("100!", 100.0, (success) => {});

	}
}