package cn.fpga.score;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;

/** Drafts survive a disconnect; confirmations only belong to the current connection. */
public final class ControlState {
    public enum Selection { OFF, DRAFT, CONFIRMED }
    private static final class Value {
        final int section;
        String draft,confirmed;
        Value(int section,String draft){this.section=section;this.draft=draft;}
    }
    private final Map<String,Value> values=new LinkedHashMap<>();
    private boolean connected,busy;
    public void edit(String key,int section,String draft){
        Value value=values.get(key);
        if(value==null)values.put(key,new Value(section,draft));else value.draft=draft;
    }
    public void confirm(String key,String confirmed){value(key).confirmed=confirmed;}
    public boolean observe(String key,String confirmed){
        Value value=value(key);boolean follow=value.confirmed==null||!dirty(key);
        if(follow)value.draft=confirmed;value.confirmed=confirmed;return follow;
    }
    public String confirmed(String key){return value(key).confirmed;}
    public boolean dirty(String key){Value value=value(key);return value.confirmed==null||!Objects.equals(value.draft,value.confirmed);}
    public Selection selection(String key,String option){
        Value value=value(key);
        if(Objects.equals(value.draft,option)&&dirty(key))return Selection.DRAFT;
        return value.confirmed!=null&&Objects.equals(value.confirmed,option)?Selection.CONFIRMED:Selection.OFF;
    }
    public boolean pending(int section){
        if(!connected)return false;
        for(Map.Entry<String,Value> entry:values.entrySet())if(entry.getValue().section==section&&dirty(entry.getKey()))return true;
        return false;
    }
    public void connected(boolean connected){
        this.connected=connected;
        if(!connected)for(Value value:values.values())value.confirmed=null;
    }
    public void busy(boolean busy){this.busy=busy;}
    public boolean enabled(){return connected&&!busy;}
    public static String numbers(String draft){
        String clean=draft.replaceAll("\\s","");StringBuilder normalized=new StringBuilder();
        try{for(String field:clean.split(",",-1)){if(normalized.length()>0)normalized.append(',');normalized.append(Integer.parseInt(field));}}
        catch(NumberFormatException invalid){return clean;}return normalized.toString();
    }
    private Value value(String key){
        Value value=values.get(key);if(value==null)throw new IllegalArgumentException("Unknown control: "+key);return value;
    }
}
