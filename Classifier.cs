using UnityEngine;
using System.Collections.Generic;

public class Classifier : MonoBehaviour
{
	private Dictionary<Vector4, List<Vector4>> goodSolutions = new Dictionary<Vector4, List<Vector4>>();
	private Dictionary<Vector4, List<Vector4>> badSolutions = new Dictionary<Vector4, List<Vector4>>();
	private Vector4 recentChoice;
	private Vector4 previousChoice;

	public void Learn(int[] indexOptions, Vector2[] positionOptions, float[] timeOptions, out int index, out Vector2 position, out float time)
	{
		List<Vector4> badSolutions = GetSolutions(recentChoice, false);
		do
		{
			index = Random.Range(0, indexOptions.Length);
			position = positionOptions[Random.Range(0, positionOptions.Length)];
			time = timeOptions[Random.Range(0, timeOptions.Length)];
		}
		while(badSolutions.Contains(new Vector4(index, position.x, position.y, time)));

		previousChoice = recentChoice;
		recentChoice = new Vector4(index, position.x, position.y, time);
	}

	public void Predict(out int index, out Vector2 position, out float time)
	{
		List<Vector4> goodSolutions = GetSolutions(previousChoice, true);
		Vector4 choice = goodSolutions[Random.Range(0, goodSolutions.Count)];

		index = Mathf.RoundToInt(choice.x);
		position = new Vector2(choice.y, choice.z);
		time = choice.w;
	}

	public void Feedback(bool isGood)
	{
		GetSolutions(previousChoice, isGood).Add(recentChoice);
	}

	private List<Vector4> GetSolutions(Vector4 choice, bool isGood)
	{
		Dictionary<Vector4, List<Vector4>> solutions = isGood ? goodSolutions : badSolutions;
		if(solutions.ContainsKey(choice))
		{
			return solutions[choice];
		}

		return new List<Vector4>();
	}
}

