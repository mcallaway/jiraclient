/*
 * Copyright (C)  2010 Mario Ivankovits
 *
 * This file is part of jira-webservice-extensions.
 *
 * Ebean is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * Ebean is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with jira-webservice-extensions; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
 */

package org.sharedSpace.jira.webservice;

import com.atlassian.jira.issue.search.SearchException;
import com.atlassian.jira.rpc.exception.RemoteAuthenticationException;
import com.atlassian.jira.rpc.exception.RemoteException;
import com.atlassian.jira.rpc.soap.JiraSoapService;
import com.atlassian.jira.rpc.soap.beans.RemoteIssue;

public interface SoapExtension extends JiraSoapService
{
	/**
	 * Used to check if the webservice is active.
	 * Calling this method returns a constant string.
	 */
	public String ping();

	/**
	 * Get linked issues with specific link type.
	 */
	public RemoteIssue[] getLinkedIssues(String token, Long issueIdFrom, String linkType) throws RemoteException;

	/**
	 * link issue
	 *
	 * @param unique if true fails if there is already a link with given type
	 * @param replace if true all other links with given type will be removed
	 */
	public void linkIssue(String token, Long issueIdFrom, Long issueIdTo, String linkType, boolean unique, boolean replace) throws RemoteException;

	/**
	 * unlink issue
	 */
	public void unlinkIssue(String token, Long issueIdFrom, Long issueIdTo, String linkType) throws RemoteException;

	/**
	 * get issue for specific worklog id
	 */
	public RemoteIssue getIssueForWorklog(String token, Long worklogId) throws RemoteException, SearchException;

	/**
	 * get custom field values for issue
	 */
	public String[] getCustomFieldValues(String token, Long customFieldId, Long issueId) throws RemoteException, SearchException;

	/**
	 * add a component to the project
	 */
	public long addComponent(String token, String projectKey, String name, String description, String lead, long assigneeType) throws RemoteException, RemoteAuthenticationException;

	/**
	 * remove a component
	 */
	public void removeComponent(String token, String projectKey, long componentId) throws RemoteException, RemoteAuthenticationException;

	/**
	 * update the name of a component
	 */
	public void updateComponent(String token, String projectKey, long componentId, String name, String description, String lead, long assigneeType) throws RemoteException, RemoteAuthenticationException;

	/**
	 * link an issue to another issue as subtask
	 */
	public void createSubtaskLink(String token, long parentIssueId, long subtaskIssueId, long issueTypeId) throws RemoteException;
}
