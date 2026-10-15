# hotfrog — questions the bug loop needs answered

## b-20261013-163534-ogsq  2026-10-15 10:06
note: arm shouldn't appear in front of the steps
question: Should the frog's gripping hand also draw behind the step, or should it stay in front while only the arm draws behind?
context: The attached menu screenshot shows green fingers over the red rung. The arm sprites are already behind the rung by Z depth; the gripping hands are in front by the explicit earlier ruling b-20260921-100824-3azi. Changing the hand order would reverse that ruling in FrogModel.model.json and doc 17.
