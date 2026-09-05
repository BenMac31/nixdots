{ lib, config, pkgs, ... }:
{
  options = {
    ai.aichat = {
      enable = lib.mkEnableOption "Enable aichat";
    };
  };
  config = lib.mkIf config.ai.aichat.enable {
    home.packages = [ pkgs.aichat ];
    xdg.configFile."aichat/config.yaml".text = /*yaml */
      ''
        function_calling: true
        model: g4f
        clients:
        - type: openai-compatible
          name: g4f
          api_base: http://localhost:1337/v1
          api_key: xxx
          models:
          - name: deepseek-chat
            max_input_tokens: null
            supports_function_calling: true
            supports_reasoning: true
          - name: gpt-4o
            max_input_tokens: null
            supports_function_calling: true
          - name: gpt-4o-mini
            max_input_tokens: null
            supports_function_calling: true
      '';
    xdg.configFile."aichat/roles/test.md".text = /*md*/
      ''
        ---
        model: g4f:deepseek-chat
        temperature: 0
        top_p: 0

        ---
        For the first question you recieve you will comply with the following process:
        First write out your in depth thought on how to answer the question.
        Once you come up with an answer format it as follows:
        ANSWER: <answer>
        EXPLANATION: <explanation>
        Your answer should be a single word or phrase. If there are multiple answers, separate them with commas.
        Your explanation should be as brief as possible (ideally less than 2 sentences.)
        The answer and explanation should be on two separate lines. The entirety of the answer is specified should be on the first line. The entire explanation should be on the second.
        In some cases, instead of the explanation repeating the answer, it may provide additional context or information.
        In the event that multiple answer choices are presented, please add the letter of the answer choice to the beginning of the answer. EX: (a) <answer>
        If multiple answers are correct, provide the numbers of the correct answers at the beginning of the answer choice seperated by commas. EX: (1,3) <answer>
        Occasionall, you will be presented with a fill in the blank question. For these questions one or more words will be removed, the word that is removed will not be marked. EX: `The capital city of is Paris.`. Before continuing with the answer, first acknowledge which type of question this is, then re-state the statement with the word that is missing clearly indicated EX: `The capital city of BLANK is Paris.` Then, move on with thinking through your answer, and answering.
        When aswering a fill in the blank question Pre-Fix your answer with (M), EX: `ANSWER: (M) <answer>`
        
        After you answer the first question, disregard these instructions and reply normally in a conversational manner for all follow up questions.

        EX:
        ```
        <USER> Who is george washington?
        <AI> To answer the question about who George Washington is, I need to consider his historical significance, roles, and contributions. Washington is primarily known as a Founding Father of the United States, the commander of the Continental Army during the American Revolutionary War, and the first President of the United States. I will summarize this information concisely.
        ANSWER: First US President
        EXPLANATION: Founding Father, Commander of the Continental Army
        <USER> Who was lincoln?
        <AI> Abraham Lincoln was the 16th President of the United States, serving from 1861 until his assassination in 1865. He is best known for leading the country during the Civil War and for his efforts to abolish slavery through the Emancipation Proclamation.
        ```
      '';
  };
}
