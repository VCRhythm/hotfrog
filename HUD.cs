using UnityEngine;
using System.Collections;
using TMPro;

public class HUD : MonoBehaviour {

	public int BugsCaught { get { return bugsCaught;} set { bugsCaught = value; if(canChangeFlyCount) UpdateFlyCount();} }
	public int StepsClimbed { get { return stepsClimbed; } set { 
			stepsClimbed = value;
			stepCountText.SetText("{0}", value);
			
			if(value == newHighScore)
			{
				NewHighScore();
			}
			else if( value > 0 && value % 10 == 0)
			{
				Base10Score();
			}
		} 
	}
	[HideInInspector] public bool canChangeFlyCount = true;

	TextMeshProUGUI stepCountText;
	Animator stepCountAnimator;
	TextMeshProUGUI flyCountText;
	TextMeshProUGUI highScoreText;

	int bugsCaught = 0;
	int newHighScore = -1;
	int stepsClimbed = 0;

	void Awake()
	{
		stepCountText = transform.FindChild("StepCount").GetComponent<TextMeshProUGUI>();
		stepCountAnimator = stepCountText.GetComponent<Animator>();
		highScoreText = GameObject.Find ("HighScore").GetComponent<TextMeshProUGUI>();
		flyCountText = GameObject.Find ("FlyCount").GetComponent<TextMeshProUGUI>();
	}
	
	public IEnumerator ChangeBugCount(int changeAmount)
	{
		int oldBugsCaught = bugsCaught;
		bugsCaught += changeAmount;
		VariableManager.Instance.SaveBugs(bugsCaught);
		
		if(changeAmount < 0)
		{
			while(oldBugsCaught > bugsCaught)
			{
				flyCountText.SetText("{0}", --oldBugsCaught);
				yield return new WaitForFixedUpdate();
			}
		}
		else
		{
			while(oldBugsCaught < bugsCaught)
			{
				flyCountText.SetText("{0}", ++oldBugsCaught);
				AudioManager.Instance.Play(AudioManager.Instance.flySound);
				yield return new WaitForFixedUpdate();
			}
		}
	}

	public void UpdateFlyCount()
	{
		flyCountText.SetText("{0}", bugsCaught);
	}

	public void SetInitialStats()
	{
		highScoreText.color = Color.white;
		canChangeFlyCount = true;
			
		//Update Scoreboard
		if(VariableManager.Instance.HighScore > 0)
			newHighScore = VariableManager.Instance.HighScore + 1;
			
		UpdateFlyCount();
		StepsClimbed = 0;
	}

	private void NewHighScore()
	{
		AudioManager.Instance.Play (AudioManager.Instance.highScoreSound);
	
		stepCountAnimator.SetBool("IsHighScore", true);
		stepCountAnimator.SetTrigger("IsBase10");
	}

	private void Base10Score()
	{
		AudioManager.Instance.Play (AudioManager.Instance.base10Sound);
		stepCountAnimator.SetBool("IsHighScore", false);
		stepCountAnimator.SetTrigger("IsBase10");
	}
}
